//! Handle Keyboard Events using the [Kitty Keyboard
//! protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/#functional)
//! (KKP). Much of the implementation is translated from Crosterm-rs
//!

const std = @import("std");
const builtin = @import("builtin");
pub const keycodes = @import("keyevents.zig");
const event_queue = @import("event_queue.zig");
const testing = std.testing;
const io = std.io;
const fs = std.fs;

const Mutex = std.Thread.Mutex;
const AlternateKeyCodes = keycodes.AlternateKeyCodes;
const KeyEvent = keycodes.KeyEvent;
const KeyCode = keycodes.KeyCode;
const KeyModifier = keycodes.KeyModifier;
pub const ProgressiveEnhancements = @import("kkp_enahancements.zig").ProgressiveEnhancements;

const CSI = "\x1B[";
const READER_BUF_SIZE = 1024;
const ESC = '\x1B';

const InternalReaderMutex = struct {
    mutex: Mutex = Mutex{},
    _inner: EventReader = EventReader.init(),

    inline fn lock(self: *InternalReaderMutex) *EventReader {
        self.mutex.lock();
        return &self._inner;
    }

    inline fn unlock(self: *InternalReaderMutex) void {
        self.mutex.unlock();
    }
};

var INTERNAL_READER_GUARD = InternalReaderMutex{};

const ReaderEventTag = enum {
    key_event,
    progressive_enhancement,
    primary_device_attribute,
};

const PrimaryDeviceAttribute = struct {};

/// Internal ReaderEvent so that we can use one reader to parse differnt kinds
/// of events. Generally only KeyEvents should be reported to the user.
const ReaderEvent = union(ReaderEventTag) {
    key_event: KeyEvent,
    progressive_enhancement: ProgressiveEnhancements,
    primary_device_attribute: PrimaryDeviceAttribute,
};

/// Reads from stdin and returns an ArrayList of KeyEvents. It is
/// responsibility of caller to free the list;
pub fn read(allocator: std.mem.Allocator) !std.ArrayList(KeyEvent) {
    const reader = INTERNAL_READER_GUARD.lock();
    defer INTERNAL_READER_GUARD.unlock();
    _ = try reader.poll(allocator);
    var list = std.ArrayList(KeyEvent).init(allocator);
    while (reader.next(allocator, true)) |event| {
        switch (event) {
            .key_event => |ke| try list.append(ke),
            else => {},
        }
    }
    return list;
}

/// Queries terminal to find support for progressive enhancements
pub fn detectProgressivEnhancementSupport(allocator: std.mem.Allocator) !bool {
    // KKP says to use the query for current flags, and then
    // send a query for the Primary Device Attribute.
    const reader = INTERNAL_READER_GUARD.lock();
    defer INTERNAL_READER_GUARD.unlock();
    const query = "\x1B[?u\x1B[c";
    const fh = try fs.openFileAbsolute("/dev/tty", .{
        .mode = .read_write,
        .allow_ctty = true,
    });
    _ = try fh.write(query);
    _ = try reader.poll(allocator);
    while (reader.*.next(allocator, false)) |response| {
        std.debug.print("{?}", .{response});
        switch (response) {
            .progressive_enhancement => {
                while (reader.*.next(allocator, false)) |r| {
                    switch (r) {
                        .primary_device_attribute => break,
                        else => {},
                    }
                }
                return true;
            },
            .primary_device_attribute => return false,
            else => {},
        }
        // FIXME: THis isn't right, This function needs be fallible, and just try to check in case
        // We havn't gotten a response
    }
    return false;
}

/// Push the Progressive enhancements onto the stack. Should be done at the end of the program
/// if enhancements were pushed onto the terminal stack. Also if using Alternate Screen then
/// should be done after alternate screen is entered.
pub fn pushProgressiveEnhancements(flags: ProgressiveEnhancements) !void {
    const stdout = io.getStdOut();
    // SAFTEY: ProgressiveEnhancements can only be at most a 5bit integer
    // (stored in 1 byte), so we can limit this buffer to 2 digits
    var flags_buf = [_]u8{ 0, 0 };
    const flags_fmt = try std.fmt.bufPrint(&flags_buf, "{d}", .{@as(u8, @bitCast(flags))});

    // \x1B, [, >, \d, (\d), u (at most 6 bytes)
    var outbuf = [_]u8{ 0, 0, 0, 0, 0, 0 };
    const out_fmt = try std.fmt.bufPrint(&outbuf, "\x1b[>{s}u", .{flags_fmt});
    _ = try stdout.write(out_fmt);
}

/// Pop the Progressive enhancements from the stack. Should be done at the end of the program
/// if enhancements were pushed onto the terminal stack. Also If using Alternate Screen then
/// should be done before alternate screen is exited.
pub fn popProgressiveEnhancements() !void {
    const stdout = io.getStdOut();
    _ = try stdout.write("\x1B[<u");
}

/// Read Input and generate an Event stream
const EventReader = struct {
    raw_buffer: event_queue.RingBuffer(u8, READER_BUF_SIZE),

    pub fn init() EventReader {
        const raw_buffer = event_queue.RingBuffer(u8, READER_BUF_SIZE).init();
        return EventReader{ .raw_buffer = raw_buffer };
    }

    // Poll stdin for events. Not using std.Poller because it's more general than I need.
    // Return's true when reader has events ready to parse
    pub fn poll(self: *EventReader, allocator: std.mem.Allocator) !bool {
        const stdin = io.getStdIn();
        var inbuff = [_]u8{0} ** READER_BUF_SIZE;
        var poller = std.io.poll(allocator, enum { stdin }, .{ .stdin = stdin });
        defer poller.deinit();
        const isReady = try poller.poll();
        if (isReady) {
            const n = poller.fifo(.stdin).read(&inbuff);
            try self.raw_buffer.pushBuffer(inbuff[0..n]);
            return true;
        }
        // FIXME: Do error handling
        return false;
    }

    /// Parse the In Buffer
    /// Panics on Allocator Error
    pub fn next(self: *EventReader, allocator: std.mem.Allocator, more: bool) ?ReaderEvent {
        var more_available = more;
        var offset: usize = 1;
        // Most Events will not be more than 16 bytes long, I assume;
        var inbuff = std.ArrayList(u8).initCapacity(allocator, 16) catch {
            @panic("Allocation Error");
        };
        defer inbuff.deinit();

        while (self.raw_buffer.pop()) |byte| : (offset += 1) {
            more_available = offset < self.raw_buffer.count or more;
            inbuff.append(byte) catch @panic("Allocation Error");
            // TODO: Since we are just using an ArrayList now, all that @memcopy that this does
            // could be done simpler by just peeking the value into the inbuff. Worth a thought.

            const res = parseEvent(inbuff.items, more_available) catch {
                // Cannot parse this set of bytes as an event, lets shift over
                _ = inbuff.orderedRemove(0);
                continue;
            };
            if (res) |event| {
                // TODO: drain the buffer
                //
                // std.debug.print("Triggering sequence: {?}", .{inbuff});
                return event;
            }
        }
        // There is nothing to parse
        return null;
    }
};

fn parseEvent(parse_buffer: []const u8, more: bool) !?ReaderEvent {

    // For Legacy Encoding there are 3 Forms we look out for that we want to make sure we
    // handle for escaped events:
    //
    // Form 1: CSI number ; modifier ~
    // Form 2: CSI 1 ; modifier {ABCDFHPQRS}
    // Form 3: SS3 {ABCDFHPQRS}
    //
    // Form 1 and 2 are handled by specialized CSI function
    // Other Keys are handled raw (i.e A is A, etc.)

    switch (parse_buffer[0]) {
        // | `ESC` | 27      | 033   | 0x1B | `\e`[*](#escape) | `^[` | Escape character           |
        0x1B => {
            if (parse_buffer.len == 1) {
                if (more) {
                    // Possible Esc sequence
                    return null;
                } else {
                    return ReaderEvent{
                        .key_event = KeyEvent{
                            .code = KeyCode.Esc,
                            .modifier = KeyModifier{},
                        },
                    };
                }
            } else {
                return switch (parse_buffer[1]) {
                    // SS3 {ABCDEFHPQRS}
                    'O' => try handleSS3Code(parse_buffer),
                    '[' => handleCSI(parse_buffer),
                    // Sometimes an Escape, is just an Escape...with an alt?
                    0x1B => ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode.Esc, .modifier = KeyModifier.alt() } },
                    else => {
                        var event = try parseEvent(parse_buffer[1..], more);
                        if (event) |*alt_event| {
                            switch (alt_event.*) {
                                ReaderEventTag.key_event => |*ke| ke.*.modifier.alt = true,
                                else => {},
                            }
                            return event;
                        }
                        return null;
                    },
                };
            }
        },

        // CO codes
        // https://sw.kovidgoyal.net/kitty/keyboard-protocol/#id10
        //
        //
        // RE: Why not \n? This is from Crossterm
        // > Issue #371: \n = 0xA, which is also the keycode for Ctrl+J. The only reason we get
        // > newlines as input is because the terminal converts \r into \n for us. When we
        // > enter raw mode, we disable that, so \n no longer has any meaning - it's better to
        // > use Ctrl+J. Waiting to handle it here means it gets picked up later
        //
        // Since for now we don't expect this to be used in a way where the terminal is not
        // in raw mode we can ignore \n.
        // FIXME: Before releasing this as a library (if we do that), we will need to fix this.

        0x0 => return ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = ' ' }, .modifier = KeyModifier.control() } },
        0x01...0x07, 0x0A...0x0C, 0x0E...0x1A => |c| {
            return ReaderEvent{ .key_event = KeyEvent{
                .code = KeyCode{ .Char = (c - 0x1 + 'a') },
                .modifier = KeyModifier.control(),
            } };
        },
        // Kity Has this as Backspace, Some terminals won't. I'd rather give up on terminfo and just
        // Use _a_ standard. This appears to be what crossterm-rs decided to do as well.
        0x08 => return ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode.Backspace, .modifier = KeyModifier.control() } },
        0x09 => return ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode.Tab, .modifier = KeyModifier{} } },
        // 0x0A..0x0C -> Are Already Handled
        0x0D => return ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode.Enter, .modifier = KeyModifier{} } },
        // 0x0E..0x1B -> Are Already Handled
        0x1C...0x1d => |c| {
            return ReaderEvent{ .key_event = KeyEvent{
                .code = KeyCode{ .Char = (c - 0x1C + '\\') },
                .modifier = KeyModifier.control(),
            } };
        },
        0x1E => return ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = '~' }, .modifier = KeyModifier.control() } },
        0x1F => return ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = '?' }, .modifier = KeyModifier.control() } },
        0x20 => return ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = ' ' }, .modifier = KeyModifier{} } },
        0x7F => return ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode.Backspace, .modifier = KeyModifier{} } },
        else => {
            // **Note** This is needed if progressive enhancement 0b1000 has been sent (Send
            // All keys as escape codes)
            const char = try parseUtf8Char(parse_buffer);
            if (char) |c| {
                return ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = c }, .modifier = KeyModifier{} } };
            }
            return null;
        },
    }
}

/// Handle the CSI Input Sequence and Generate a key event. This handles both legacy and
/// KKP events
fn handleCSI(buff: []const u8) !?ReaderEvent {

    // Key Sequences like this are of mode:
    //      CSI unicode-key-code:alternate-key-codes ; modifiers:event-type ; text-as-codepoints [u~]
    //
    // CSI is the byte_sequence "\x1B["
    //
    // In the general case. Some of these fields are optional
    // To be exact the folowing forms are OK.
    //
    // Legacy:
    // FORM 1: CSI number ; [modifier] ~
    // FORM 2: CSI [1 ; modifier] {ABCDEFHPQS}
    //
    // KKP:
    // GENERAL: CSI unicode-key-code[:alternate-key-codes] ; [modifiers:event-type] ; [text-as-codepoints] u
    // SPECIAL: CSI unicode-key-code u
    //
    // TODO: Do the text-as-codepoints part
    // Text Codepoints are a progressive enhancement, Let's ingore them for now

    std.debug.assert(std.mem.eql(u8, buff[0..2], CSI));

    // Early return if there are not enough bytes, we'll go back to get more
    if (buff.len == 2) {
        return null;
    }

    // Legacy KeyCodes
    var event: ?KeyEvent = null;
    if (buff.len == 3) {
        // Second Form, with no `number` parameter
        event = switch (buff[2]) {
            'A' => KeyEvent{ .code = KeyCode.Up, .modifier = KeyModifier{} },
            'B' => KeyEvent{ .code = KeyCode.Down, .modifier = KeyModifier{} },
            'C' => KeyEvent{ .code = KeyCode.Right, .modifier = KeyModifier{} },
            'D' => KeyEvent{ .code = KeyCode.Left, .modifier = KeyModifier{} },
            'E' => KeyEvent{ .code = KeyCode.KeypadBegin, .modifier = KeyModifier{} },
            'H' => KeyEvent{ .code = KeyCode.Home, .modifier = KeyModifier{} },
            'F' => KeyEvent{ .code = KeyCode.End, .modifier = KeyModifier{} },
            // CSI Z could reasonably be <S-Tab> or <C-S-Tab>
            // If the user wants specificity they can set the progressive enhancements
            'Z' => KeyEvent{ .code = KeyCode.Tab, .modifier = KeyModifier.shift() },
            else => return null,
        };
    } else if (buff[2] == '?') {
        const enhancement = try parseTerminalQueryResponses(buff);
        return enhancement;
    } else if (isMember(buff[buff.len - 1], "~ABCDEFHPQS")) {
        event = try parseLegacyCSI(buff);
    } else if (buff[buff.len - 1] == 'u') {
        event = try parseKKPCSI(buff);
    } else {
        return null;
    }
    if (event) |ke| {
        return ReaderEvent{ .key_event = ke };
    } else {
        return null;
    }
}

fn isMember(value: u8, comptime group: []const u8) bool {
    for (group) |g| {
        if (value == g) {
            return true;
        }
    }
    return false;
}

// Parses the Legacy Characters form CSI
fn parseLegacyCSI(buff: []const u8) !?KeyEvent {
    // Legacy CSI Key codes have two major forms:
    // CSI number [; modifier] ~
    // CSI [1 ; modifier] {ABCDEFHPQS}

    var code: KeyCode = undefined;
    var codepoint: u16 = undefined;
    var modifier: KeyModifier = KeyModifier{};

    var token_stream = std.mem.splitSequence(u8, buff[2..], ";");
    const number = token_stream.first();
    const modifier_and_term = token_stream.next();

    if (modifier_and_term) |modifier_plus| {
        // The first byte is what caries the modifier
        if (modifier_plus.len == 0) {
            // We havn't gotten the modifier yet
            return null;
        }
        const m = try std.fmt.parseInt(u9, modifier_plus[0 .. modifier_plus.len - 1], 10);
        modifier = parseModifier(m);
        codepoint = try std.fmt.parseInt(u16, number, 10);
    } else if (buff[buff.len - 1] == '~') {
        // Form 1 sans modifier
        codepoint = try std.fmt.parseInt(u16, number[0 .. number.len - 1], 10);
    } else {
        // Form 2 sans modifier. Per the spec there is actually no codepoint
        // available to be read when modifiers are not present, but in order to
        // keep the logic the same, we will assign the codepoint that is implied.
        codepoint = 1;
    }

    if (codepoint == 1) {
        // In this Case we are expecting Form 2 of the Legacy Functional keys
        // CSI 1 ; Modifier { ABCDFH } So there needs to be 6 bytes
        if (buff.len < 6) {
            return null;
        }
        std.debug.assert(std.mem.eql(u8, buff[2..4], "1;"));
        code = switch (buff[5]) {
            'A' => KeyCode.Up,
            'B' => KeyCode.Down,
            'C' => KeyCode.Right,
            'D' => KeyCode.Left,
            'E' => KeyCode.KeypadBegin,
            'H' => KeyCode.Home,
            'F' => KeyCode.End,
            'P' => KeyCode{ .F = 1 },
            'Q' => KeyCode{ .F = 2 },
            'S' => KeyCode{ .F = 4 },
            else => return error.CouldNotParse,
        };
    } else {
        // Form 1 Legacy encoding
        code = switch (codepoint) {
            2 => KeyCode.Insert,
            3 => KeyCode.Delete,
            5 => KeyCode.PageUp,
            6 => KeyCode.PageDown,
            15 => KeyCode{ .F = 5 },
            // This will not work because  17 (and 18,19,20 etc) is not a character.. Sigh
            17...21 => |v| out: {
                const val: u8 = @truncate(v - 11);
                break :out KeyCode{ .F = val };
            },
            23...24 => |v| out: {
                const val: u8 = @truncate(v - 12);
                break :out KeyCode{ .F = val };
            },
            29 => KeyCode.Menu,
            57427 => KeyCode.KeypadBegin,
            else => return error.CouldNotParse,
        };
    }
    return KeyEvent{ .code = code, .modifier = modifier };
}

fn parseTerminalQueryResponses(buff: []const u8) !?ReaderEvent {
    if (buff[buff.len - 1] == 0) {
        return null;
    }
    return switch (buff[buff.len - 1]) {
        'c' => out: {
            break :out ReaderEvent{ .primary_device_attribute = .{} };
        },
        'u' => out: {
            const inner = try ProgressiveEnhancements.from_str(buff[3 .. buff.len - 1]);
            break :out ReaderEvent{ .progressive_enhancement = inner };
        },
        else => null,
    };
}

fn parseKKPCSI(buff: []const u8) !?KeyEvent {
    // GENERAL: CSI unicode-key-code[[:alternate-key-codes] [; modifiers:event-type] ; [text-as-codepoints]] u
    // SPECIAL: CSI unicode-key-code u
    var code: KeyCode = undefined;
    var modifier: KeyModifier = undefined;
    var codepoint: []const u8 = undefined;
    var alternates = AlternateKeyCodes{};
    var action: ?keycodes.KeyAction = null;

    var token_stream = std.mem.splitSequence(u8, buff[2..], ";");
    const codepoint_section = token_stream.first();
    const modifier_section = token_stream.next();
    const text_codepoints = token_stream.next();
    _ = text_codepoints;
    if (modifier_section) |mod_section| {
        // General Case.

        // XXX: We are ignoring text-as-codepoints for now, as we
        // are not really supporting progressive enhancements at this point.
        // It will be some of the next things we work on.
        var codepoint_seq = std.mem.splitSequence(u8, codepoint_section, ":");
        codepoint = codepoint_seq.first();
        const shifted = codepoint_seq.next();
        const base_layout = codepoint_seq.next();

        if (shifted) |k| {
            if (k.len != 0) {
                const char = try parseUtf8Char(k);
                if (char) |c| {
                    alternates.shifted_key = KeyCode{ .Char = c };
                }
            }
        }

        if (base_layout) |k| {
            if (k.len != 0) {
                const char = try parseUtf8Char(k);
                if (char) |c| {
                    alternates.base_layout_key = KeyCode{ .Char = c };
                }
            }
        }

        var modifier_seq = std.mem.splitSequence(u8, mod_section, ":");
        // Find out if the final character is u, and exclude it if so
        const mod = modifier_seq.first();
        const end = if (mod[mod.len - 1] == 'u') mod.len - 1 else mod.len;
        const m = try std.fmt.parseInt(u9, mod[0..end], 10);
        modifier = parseModifier(m);
        if (modifier_seq.next()) |act| {
            action = switch (act[0]) {
                '2' => keycodes.KeyAction.repeat,
                '3' => keycodes.KeyAction.release,
                else => keycodes.KeyAction.press,
            };
        }
        // TODO: Handle KeyPress Events as well
        // ALSO, The docs seem to indicate that A should be sent in this form.
        // We are not expecting it. We'll need to build a simple tool
        // that can test our output and see what we get
    } else {
        // This should be the special case, a codepoint with no modifiers
        modifier = KeyModifier{};
        codepoint = codepoint_section[0 .. codepoint_section.len - 1];
    }

    code = parseUnicodeEvents(codepoint) catch res: {
        const char = try parseUtf8Char(codepoint);
        if (char) |c| {
            break :res KeyCode{ .Char = c };
        }
        // Is this right?
        return error.CouldNotParse;
    };

    return KeyEvent{ .code = code, .modifier = modifier, .alternate = alternates, .action = action };
}

fn parseUnicodeEvents(codepoint: []const u8) !KeyCode {
    const parsed = try std.fmt.parseInt(u16, codepoint, 10);
    return switch (parsed) {
        27 => KeyCode.Esc, // ESCAPE
        13 => KeyCode.Enter, // ENTER
        9 => KeyCode.Tab, // TAB
        127 => KeyCode.Backspace, // BACKSPACE
        57358 => KeyCode.CapsLock, // CAPS_LOCK
        57359 => KeyCode.ScrollLock, // SCROLL_LOCK
        57360 => KeyCode.NumLock, // NUM_LOCK
        57361 => KeyCode.PrintScreen, // PRINT_SCREEN
        57362 => KeyCode.Pause, // PAUSE
        57363 => KeyCode.Menu, // MENU
        57376...57398 => |c| output: {
            // SAFETY: This is Safe because c will always be in a range where delta is < 34
            const delta: u8 = @truncate(c - 57376);
            break :output KeyCode{ .F = 13 + delta };
        }, // F13
        // Crossterm Reports these as KeyEvent State and references the "Disambiguate Escape Codes"
        // part of the protocol. I don't see where it is mentioned specifically that these are
        // coded with a state parameter, but for now I'll ignore the origin from the KeyPad and we
        // will deal with it later
        57399...57408 => |c| output: {
            // SAFETY: This is Safe because c will always be in a range where delta is < 10
            const delta: u8 = @truncate(c - 57399);
            break :output KeyCode{ .KpKey = '0' + delta };
        }, // KP_0
        57409 => KeyCode{ .KpKey = '.' }, // KP_DECIMAL
        57410 => KeyCode{ .KpKey = '/' }, // KP_DIVIDE
        57411 => KeyCode{ .KpKey = '*' }, // KP_MULTIPLY
        57412 => KeyCode{ .KpKey = '-' }, // KP_SUBTRACT
        57413 => KeyCode{ .KpKey = '+' }, // KP_ADD
        57414 => KeyCode.Enter, // KP_ENTER
        57415 => KeyCode{ .Char = '=' }, // KP_EQUAL
        // This is how Crossterm does it, but... Not really localized, maybe we ought to localize?
        57416 => KeyCode{ .Char = ',' }, // KP_SEPARATOR
        57417 => KeyCode.Left, // KP_LEFT
        57418 => KeyCode.Right, // KP_RIGHT
        57419 => KeyCode.Up, // KP_UP
        57420 => KeyCode.Down, // KP_DOWN
        57421 => KeyCode.PageUp, // KP_PAGE_UP
        57422 => KeyCode.PageDown, // KP_PAGE_DOWN
        57423 => KeyCode.Home, // KP_HOME
        57424 => KeyCode.End, // KP_END
        57425 => KeyCode.Insert, // KP_INSERT
        57426 => KeyCode.Delete, // KP_DELETE
        57428 => KeyCode{ .Media = .Play }, // MEDIA_PLAY
        57429 => KeyCode{ .Media = .Pause }, // MEDIA_PAUSE
        57430 => KeyCode{ .Media = .PlayPause }, // MEDIA_PLAY_PAUSE
        57431 => KeyCode{ .Media = .Reverse }, // MEDIA_REVERSE
        57432 => KeyCode{ .Media = .Stop }, // MEDIA_STOP
        57433 => KeyCode{ .Media = .FastForward }, // MEDIA_FAST_FORWARD
        57434 => KeyCode{ .Media = .Rewind }, // MEDIA_REWIND
        57435 => KeyCode{ .Media = .TrackNext }, // MEDIA_TRACK_NEXT
        57436 => KeyCode{ .Media = .TrackPrevious }, // MEDIA_TRACK_PREVIOUS
        57437 => KeyCode{ .Media = .Record }, // MEDIA_RECORD
        57438 => KeyCode{ .Media = .LowerVolume }, // LOWER_VOLUME
        57439 => KeyCode{ .Media = .RaiseVolume }, // RAISE_VOLUME
        57440 => KeyCode{ .Media = .MuteVolume }, // MUTE_VOLUME
        57441 => KeyCode{ .Modifier = .LeftShift }, // LEFT_SHIFT
        57442 => KeyCode{ .Modifier = .LeftControl }, // LEFT_CONTROL
        57443 => KeyCode{ .Modifier = .LeftAlt }, // LEFT_ALT
        57444 => KeyCode{ .Modifier = .LeftSuper }, // LEFT_SUPER
        57445 => KeyCode{ .Modifier = .LeftHyper }, // LEFT_HYPER
        57446 => KeyCode{ .Modifier = .LeftMeta }, // LEFT_META
        57447 => KeyCode{ .Modifier = .RightShift }, // RIGHT_SHIFT
        57448 => KeyCode{ .Modifier = .RightControl }, // RIGHT_CONTROL
        57449 => KeyCode{ .Modifier = .RightAlt }, // RIGHT_ALT
        57450 => KeyCode{ .Modifier = .RightSuper }, // RIGHT_SUPER
        57451 => KeyCode{ .Modifier = .RightHyper }, // RIGHT_HYPER
        57452 => KeyCode{ .Modifier = .RightMeta }, // RIGHT_META
        57453 => KeyCode{ .Modifier = .IsoLevel3Shift }, // ISO_LEVEL3_SHIFT
        57454 => KeyCode{ .Modifier = .IsoLevel5Shift }, // ISO_LEVEL5_SHIFT
        else => return error.CouldNotParse,
    };
}

fn getCodepoint(buff: []const u8) ![]const u8 {
    std.debug.assert(buff[buff.len - 1] == 'u');
    var end: usize = undefined;
    for (buff, 0..) |c, i| {
        end = i;
        if (c == 'u') {
            break;
        }
    }
    if (end == 0) {
        return error.CouldNotParse;
    }
    // WARN: IS THIS SAFE?
    return buff[0..end];
}

/// Handles SS3 Code
/// Must only be called when you know the buff begins with {0x1B,'O'}
fn handleSS3Code(buff: []const u8) !?ReaderEvent {
    std.debug.assert(std.mem.eql(u8, buff[0..2], &[_]u8{ 0x1b, 'O' }));

    if (buff.len == 2) {
        return null;
    } else {
        const code = switch (buff[2]) {
            'A' => KeyCode.Up,
            'B' => KeyCode.Down,
            'C' => KeyCode.Right,
            'D' => KeyCode.Left,
            'H' => KeyCode.Home,
            'F' => KeyCode.End,
            // F1-F4
            'P'...'S' => |val| KeyCode{
                .F = (1 + val - 'P'),
            },
            else => return error.CouldNotParse,
        };
        return ReaderEvent{ .key_event = KeyEvent{ .code = code, .modifier = KeyModifier{} } };
    }
}

fn parseUtf8Char(buff: []const u8) !?u21 {
    const required_bytes: u8 = switch (buff[0]) {
        // https://en.wikipedia.org/wiki/UTF-8#Description
        0x00...0x7F => 1, // 0xxxxxxx
        0xC2...0xDF => 2, // 110xxxxx 10xxxxxx
        0xE0...0xEF => 3, // 1110xxxx 10xxxxxx 10xxxxxx
        0xF0...0xF4 => 4, // 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
        0xC0, 0xC1, 0x80...0xBF, 0xF5...0xFF => return error.UnparseableEvent,
    };

    if (buff.len < required_bytes) {
        return null;
    } else {
        return try std.unicode.utf8Decode(buff[0..required_bytes]);
    }
}

inline fn parseModifier(mod: u9) KeyModifier {
    // Kitty protocol, modifier base state is 1, so we need to subract one
    const modifier = mod - 1;
    std.debug.assert(0b100000000 & modifier == 0);
    // Truncating is safe because there is no valid bit pattern for the 9th bit
    const m: u8 = @truncate(modifier);
    return @bitCast(m);
}

test "parse event 'A'" {
    testing.refAllDecls(@This());
    const res = try parseEvent(&[_]u8{'A'}, false);
    try testing.expect(std.meta.eql(res.?, ReaderEvent{ .key_event = KeyEvent{
        .code = KeyCode{ .Char = 'A' },
        .modifier = KeyModifier{},
    } }));
}

test "parse event 'A' with alternate key reporting" {
    const res = try parseEvent("\x1B[a:A;2u", false);
    try testing.expect(std.meta.eql(res.?, ReaderEvent{ .key_event = KeyEvent{
        .code = KeyCode{ .Char = 'a' },
        .modifier = KeyModifier.shift(),
        .alternate = AlternateKeyCodes{ .shifted_key = KeyCode{ .Char = 'A' } },
    } }));
}

test "parse event '󱫎'" {
    const res2 = try parseEvent("󱫎", false);
    try testing.expect(std.meta.eql(res2.?, ReaderEvent{ .key_event = KeyEvent{
        .code = KeyCode{ .Char = '󱫎' },
        .modifier = KeyModifier{},
    } }));
}

test "parse event 'è'" {
    const res2 = try parseEvent("\xc3\xa8", false);
    try testing.expect(std.meta.eql(res2.?, ReaderEvent{ .key_event = KeyEvent{
        .code = KeyCode{ .Char = 'è' },
        .modifier = KeyModifier{},
    } }));
}

test "parse event 'è' as unicode event" {
    const res2 = try parseEvent("\x1B[\xc3\xa8u", false);
    try testing.expect(std.meta.eql(res2.?, ReaderEvent{ .key_event = KeyEvent{
        .code = KeyCode{ .Char = 'è' },
        .modifier = KeyModifier{},
    } }));
}

test "parse event type" {
    const res = try parseEvent("\x1B[a:A;2:2u", false);
    try testing.expect(std.meta.eql(res.?, ReaderEvent{ .key_event = KeyEvent{
        .code = KeyCode{ .Char = 'a' },
        .modifier = KeyModifier.shift(),
        .action = .repeat,
        .alternate = AlternateKeyCodes{ .shifted_key = KeyCode{ .Char = 'A' } },
    } }));
}

test "parse escape sequence" {
    const input = "\x1BOD";
    const res = try parseEvent(input[0..], false);
    try testing.expect(std.meta.eql(res.?, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode.Left, .modifier = KeyModifier{} } }));
}

test "parse csi" {
    const input = "\x1B[1;2D";
    const res = try handleCSI(input[0..]);
    try testing.expect(std.meta.eql(res.?, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode.Left, .modifier = KeyModifier{ .shift = true } } }));
}

test "regression CSI Z" {
    const input = "\x1B[Z";
    const res = try handleCSI(input[0..]);
    try testing.expect(std.meta.eql(res.?, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode.Tab, .modifier = KeyModifier{ .shift = true } } }));
}

test "parse csi F5" {
    const input = "\x1B[15~";
    const res = try parseEvent(input[0..], false);
    try testing.expectEqual(res.?, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .F = 5 }, .modifier = KeyModifier{} } });
}

test "parse ss3" {
    const keys = [_]u8{ 'A', 'B', 'C', 'D', 'F', 'H', 'P', 'Q', 'R', 'S' };
    const codes = [_]KeyCode{
        KeyCode.Up,
        KeyCode.Down,
        KeyCode.Right,
        KeyCode.Left,
        KeyCode.End,
        KeyCode.Home,
        KeyCode{ .F = 1 },
        KeyCode{ .F = 2 },
        KeyCode{ .F = 3 },
        KeyCode{ .F = 4 },
    };
    inline for (keys, codes) |key, code| {
        const input = [_]u8{ 0x1B, 'O', key };
        const res = try handleSS3Code(input[0..]);
        try testing.expect(std.meta.eql(res.?, ReaderEvent{ .key_event = KeyEvent{ .code = code, .modifier = KeyModifier{} } }));
    }
}

test "parse c0 codes to standard representation" {
    // 'Standard' Table can be found here https://vt100.net/docs/vt100-ug/chapter3.html
    const codes = [32]std.meta.Tuple(&.{ u8, ReaderEvent }){
        .{ 0, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = ' ' }, .modifier = KeyModifier.control() } } },
        .{ 1, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'a' }, .modifier = KeyModifier.control() } } },
        .{ 2, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'b' }, .modifier = KeyModifier.control() } } },
        .{ 3, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'c' }, .modifier = KeyModifier.control() } } },
        .{ 4, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'd' }, .modifier = KeyModifier.control() } } },
        .{ 5, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'e' }, .modifier = KeyModifier.control() } } },
        .{ 6, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'f' }, .modifier = KeyModifier.control() } } },
        .{ 7, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'g' }, .modifier = KeyModifier.control() } } },
        .{ 8, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode.Backspace, .modifier = KeyModifier.control() } } },
        .{ 9, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode.Tab, .modifier = KeyModifier{} } } },
        .{ 10, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'j' }, .modifier = KeyModifier.control() } } },
        .{ 11, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'k' }, .modifier = KeyModifier.control() } } },
        .{ 12, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'l' }, .modifier = KeyModifier.control() } } },
        .{ 13, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode.Enter, .modifier = KeyModifier{} } } },
        .{ 14, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'n' }, .modifier = KeyModifier.control() } } },
        .{ 15, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'o' }, .modifier = KeyModifier.control() } } },
        .{ 16, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'p' }, .modifier = KeyModifier.control() } } },
        .{ 17, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'q' }, .modifier = KeyModifier.control() } } },
        .{ 18, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'r' }, .modifier = KeyModifier.control() } } },
        .{ 19, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 's' }, .modifier = KeyModifier.control() } } },
        .{ 20, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 't' }, .modifier = KeyModifier.control() } } },
        .{ 21, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'u' }, .modifier = KeyModifier.control() } } },
        .{ 22, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'v' }, .modifier = KeyModifier.control() } } },
        .{ 23, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'w' }, .modifier = KeyModifier.control() } } },
        .{ 24, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'x' }, .modifier = KeyModifier.control() } } },
        .{ 25, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'y' }, .modifier = KeyModifier.control() } } },
        .{ 26, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 'z' }, .modifier = KeyModifier.control() } } },
        .{ 27, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode.Esc, .modifier = KeyModifier{} } } },
        .{ 28, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = '\\' }, .modifier = KeyModifier.control() } } },
        .{ 29, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = ']' }, .modifier = KeyModifier.control() } } },
        .{ 30, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = '~' }, .modifier = KeyModifier.control() } } },
        .{ 31, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = '?' }, .modifier = KeyModifier.control() } } },
    };

    inline for (codes) |code| {
        const result = try parseEvent(&[_]u8{code.@"0"}, false);
        try testing.expect(std.meta.eql(code.@"1", result.?));
    }
}

test "parse Extended Keyboard Events" {
    const result = try parseEvent("\x1B[57428u", false);
    try testing.expect(std.meta.eql(ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Media = .Play }, .modifier = KeyModifier{} } }, result.?));
}

test "EventReader.next() works how I expect" {
    const allocator = std.testing.allocator;
    const event_stream = "\x1BOD\x1B[1;2D";
    var rb = event_queue.RingBuffer(u8, READER_BUF_SIZE).init();
    for (event_stream) |byte| {
        try rb.push(byte);
    }
    var reader = EventReader{ .raw_buffer = rb };
    const event = reader.next(allocator, false);
    try testing.expect(std.meta.eql(event.?, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode.Left, .modifier = KeyModifier{} } }));
    const event2 = reader.next(allocator, false);
    try testing.expect(std.meta.eql(event2.?, ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode.Left, .modifier = KeyModifier{ .shift = true } } }));
}

test "EventReader isn't Over Eager and reads UTF-8 as UTF-8" {
    const allocator = std.testing.allocator;
    const event_stream = "\xc3\xa8";
    var rb = event_queue.RingBuffer(u8, READER_BUF_SIZE).init();
    for (event_stream) |byte| {
        try rb.push(byte);
    }
    var reader = EventReader{ .raw_buffer = rb };
    const event = reader.next(allocator, false);
    try testing.expectEqualDeep(
        ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .Char = 232 }, .modifier = KeyModifier{} } },
        event.?,
    );
}

test "Legacy Codes do not report `~`" {
    const allocator = std.testing.allocator;
    const event_stream = "\x1B[15;2~";
    var rb = event_queue.RingBuffer(u8, READER_BUF_SIZE).init();
    for (event_stream) |byte| {
        try rb.push(byte);
    }
    var reader = EventReader{ .raw_buffer = rb };
    const event = reader.next(allocator, false);
    const expected = ReaderEvent{ .key_event = KeyEvent{ .code = KeyCode{ .F = 5 }, .modifier = KeyModifier{ .shift = true } } };
    try testing.expectEqualDeep(expected, event.?);
    const event2 = reader.next(allocator, false);
    try testing.expect(null == event2);
}

test "Progressive Enhancements supported by reader" {
    const result = try parseEvent("\x1B[?8u", false);
    try testing.expectEqualDeep(ReaderEvent{
        .progressive_enhancement = ProgressiveEnhancements{
            .report_all_keys_as_escapecodes = true,
        },
    }, result.?);
}
