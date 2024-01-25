//! Handle Keyboard Events using the [Kitty Keyboard protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/#functional).
//! Much of the implementation is translated from Crosterm-rs
//!

// Quick Reference, Keycodes will be encoded by terminal as such:
// CSI number ; modifiers [u~] (New and Legacy)
// CSI 1; modifiers [ABCDEFHPQS] (Legacy)
// 0x0d - for the Enter key (Legacy)
// 0x7f or 0x08 - for Backspace (Legacy)
// 0x09 - for Tab (Legacy)
const std = @import("std");
const keycodes = @import("keyevents.zig");
const event_queue = @import("event_queue.zig");
const testing = std.testing;
const io = std.io;
const fs = std.fs;
const KeyEvent = keycodes.KeyEvent;
const KeyCode = keycodes.KeyCode;
const KeyModifier = keycodes.KeyModifier;

const READER_BUF_SIZE = 1024;

const ReadOut = struct { [READER_BUF_SIZE]u8, usize };

/// Read Input and generate an Event stream
pub const EventReader = struct {
    event_buffer: event_queue.RingBuffer(KeyCode, READER_BUF_SIZE),

    pub fn init() EventReader {
        const event_buffer = event_queue.RingBuffer(KeyCode, READER_BUF_SIZE).init();
        return EventReader{ .event_buffer = event_buffer };
    }

    // Read values from stdin
    pub fn read() !ReadOut {
        var inbuff = [_]u8{0} ** READER_BUF_SIZE;
        const stdin = io.getStdIn();
        const n = try stdin.read(&inbuff);
        return .{ inbuff, n };
    }

    fn name_the_func(inbuff: []u8, more: bool) void {
        var start = 0;
        var more_available = more;
        var offset = 0;
        for (inbuff, 1..) |byte, i| {
            _ = byte;
            more_available = i < inbuff.len or more;

            offset = i - start;

            const res = parseEvent(inbuff[start .. start + offset], more_available) catch {
                start = i - 1;
                continue;
            };
            _ = res;
        }
    }
};

fn parseEvent(parse_buffer: []const u8, more: bool) !?KeyEvent {

    // # For Legacy Encoding there are 3 Forms we look out for that we want to make sure
    // Form 1: CSI number ; modifier ~
    // Form 2: CSI 1 ; modifier {ABCDFHPQRS}
    // Form 3: SS3 {ABCDFHPQRS}

    switch (parse_buffer[0]) {
        // | `ESC` | 27      | 033   | 0x1B | `\e`[*](#escape) | `^[` | Escape character           |
        0x1B => {
            if (parse_buffer.len == 1) {
                if (more) {
                    // Possible Esc sequence
                    return null;
                } else {
                    return KeyEvent{ .code = KeyCode.Esc, .modifier = KeyModifier{} };
                }
            } else {
                return switch (parse_buffer[1]) {
                    // SS3 {ABCDEFHPQRS}
                    'O' => try handleSS3Code(parse_buffer),
                    '[' => handleCSI(parse_buffer),
                    // Sometimes an Escape, is just an Escape...with an alt?
                    0x1B => KeyEvent{ .code = KeyCode.Esc, .modifier = KeyModifier.alt() },
                    else => {
                        var event = try parseEvent(parse_buffer[1..], more);
                        if (event) |*alt_event| {
                            alt_event.*.modifier.alt = true;
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

        0x0 => return KeyEvent{ .code = KeyCode{ .Char = ' ' }, .modifier = KeyModifier.control() },
        0x01...0x07, 0x0A...0x0C, 0x0E...0x1A => |c| {
            return KeyEvent{
                .code = KeyCode{ .Char = (c - 0x1 + 'a') },
                .modifier = KeyModifier.control(),
            };
        },
        // Kity Has this as Backspace, Some terminals won't. I'd rather give up on terminfo and just
        // Use _a_ standard. This appears to be what crossterm-rs decided to do as well.
        0x08 => return KeyEvent{ .code = KeyCode.Backspace, .modifier = KeyModifier.control() },
        0x09 => return KeyEvent{ .code = KeyCode.Tab, .modifier = KeyModifier{} },
        // 0x0A..0x0C -> Are Already Handled
        0x0D => return KeyEvent{ .code = KeyCode.Enter, .modifier = KeyModifier{} },
        // 0x0E..0x1B -> Are Already Handled
        0x1C...0x1d => |c| {
            return KeyEvent{
                .code = KeyCode{ .Char = (c - 0x1C + '\\') },
                .modifier = KeyModifier.control(),
            };
        },
        0x1E => return KeyEvent{ .code = KeyCode{ .Char = '~' }, .modifier = KeyModifier.control() },
        0x1F => return KeyEvent{ .code = KeyCode{ .Char = '?' }, .modifier = KeyModifier.control() },
        0x20 => return KeyEvent{ .code = KeyCode{ .Char = ' ' }, .modifier = KeyModifier{} },
        0x7F => return KeyEvent{ .code = KeyCode.Backspace, .modifier = KeyModifier{} },
        else => {
            const char = try parseUtf8Char(parse_buffer);
            if (char) |c| {
                return KeyEvent{ .code = KeyCode{ .Char = c }, .modifier = KeyModifier{} };
            }
            return null;
        },
    }
}

fn handleCSI(buff: []const u8) !?KeyEvent {
    std.debug.assert(std.mem.eql(u8, buff[0..2], &[_]u8{ 0x1B, '[' }));

    if (buff.len == 2) {
        return null;
    }

    var event: ?KeyEvent = null;
    if (buff.len == 3) {
        // Second Form, with no `number` parameter
        event = switch (buff[2]) {
            'A' => KeyEvent{ .code = KeyCode.Up, .modifier = KeyModifier{} },
            'B' => KeyEvent{ .code = KeyCode.Down, .modifier = KeyModifier{} },
            'C' => KeyEvent{ .code = KeyCode.Right, .modifier = KeyModifier{} },
            'D' => KeyEvent{ .code = KeyCode.Left, .modifier = KeyModifier{} },
            'H' => KeyEvent{ .code = KeyCode.Home, .modifier = KeyModifier{} },
            'F' => KeyEvent{ .code = KeyCode.End, .modifier = KeyModifier{} },
            else => return error.CouldNotParse,
        };
    } else {
        event = switch (buff[2]) {
            0x1 => output: {
                if (buff.len < 6) {
                    // In this Case we are expecting Form 2 of the Legacy Functional keys
                    // CSI 1 ; Modifier { ABCDFH } So there needs to be 6 bytes
                    return null;
                }
                std.debug.assert(std.mem.eql(u8, buff[2..4], &[_]u8{ 0x1, ';' }));
                const modifier = parseModifier(buff[4]);
                const code: KeyCode = switch (buff[5]) {
                    'A' => KeyCode.Up,
                    'B' => KeyCode.Down,
                    'C' => KeyCode.Right,
                    'D' => KeyCode.Left,
                    'H' => KeyCode.Home,
                    'F' => KeyCode.End,
                    else => return error.CouldNotParse,
                };
                break :output KeyEvent{ .code = code, .modifier = modifier };
            },
            0x2...0xFF => |c| output: {
                const last_char = buff[buff.len - 1];
                const code: KeyCode = out: {
                    if (last_char == '~') {
                        // Form 1 Legacy encoding
                        switch (c) {
                            2 => break :out KeyCode.Insert,
                            3 => break :out KeyCode.Delete,
                            5 => break :out KeyCode.PageUp,
                            6 => break :out KeyCode.PageDown,
                            15 => break :out KeyCode{ .F = 5 },
                            17...21 => |v| break :out KeyCode{ .F = v - 11 },
                            23...24 => |v| break :out KeyCode{ .F = v - 12 },
                            29 => break :out KeyCode.Menu,
                            else => return error.CouldNotParse,
                        }
                    } else if (last_char == 'u') {
                        // Unimplemented Stuff for the Kitty Keybaord Protocol
                        // CSI unicode-key-code:alternate-key-codes ; modifiers:event-type ; text-as-codepoints u

                        // Check Terminal Status?
                        var splits = std.mem.splitSequence(u8, buff[2 .. buff.len - 2], ";");
                        const codepoint_section: []const u8 = splits.next() orelse return error.CouldNotParse;

                        // TODO: Fix this when implementing alternate-key-codes
                        var codepoint_seq = std.mem.tokenizeSequence(u8, codepoint_section, ":");
                        const codepoint = (codepoint_seq.next() orelse return error.CouldNotParse);
                        const keycode = parseUnicodeEvents(codepoint);

                    } else {
                        return error.CouldNotParse;
                    }
                };
                const modifier = parseModifier(buff[buff.len - 2]);
                break :output KeyEvent{ .code = code, .modifier = modifier };
            },
            else => null,
        };
    }
    return event;
}

fn parseUnicodeEvents(codepoint: []const u8) !KeyCode {
    return switch (std.fmt.parseInt(codepoint)) {
27 => KeyCode.Escape,// ESCAPE
13 => // ENTER
9 => // TAB
127 => // BACKSPACE
2 => // INSERT
3 => // DELETE
1 => // LEFT
1 => // RIGHT
1 => // UP
1 => // DOWN
5 => // PAGE_UP
6 => // PAGE_DOWN
1 => // HOME
1 => // END
57358 => // CAPS_LOCK
57359 => // SCROLL_LOCK
57360 => // NUM_LOCK
57361 => // PRINT_SCREEN
57362 => // PAUSE
57363 => // MENU
1 => // F1
1 => // F2
13 => // F3
1 => // F4
15 => // F5
17 => // F6
18 => // F7
19 => // F8
20 => // F9
21 => // F10
23 => // F11
24 => // F12
57376 => // F13
57377 => // F14
57378 => // F15
57379 => // F16
57380 => // F17
57381 => // F18
57382 => // F19
57383 => // F20
57384 => // F21
57385 => // F22
57386 => // F23
57387 => // F24
57388 => // F25
57389 => // F26
57390 => // F27
57391 => // F28
57392 => // F29
57393 => // F30
57394 => // F31
57395 => // F32
57396 => // F33
57397 => // F34
57398 => // F35
57399 => // KP_0
57400 => // KP_1
57401 => // KP_2
57402 => // KP_3
57403 => // KP_4
57404 => // KP_5
57405 => // KP_6
57406 => // KP_7
57407 => // KP_8
57408 => // KP_9
57409 => // KP_DECIMAL
57410 => // KP_DIVIDE
57411 => // KP_MULTIPLY
57412 => // KP_SUBTRACT
57413 => // KP_ADD
57414 => // KP_ENTER
57415 => // KP_EQUAL
57416 => // KP_SEPARATOR
57417 => // KP_LEFT
57418 => // KP_RIGHT
57419 => // KP_UP
57420 => // KP_DOWN
57421 => // KP_PAGE_UP
57422 => // KP_PAGE_DOWN
57423 => // KP_HOME
57424 => // KP_END
57425 => // KP_INSERT
57426 => // KP_DELETE
1 => // KP_BEGIN
57428 => // MEDIA_PLAY
57429 => // MEDIA_PAUSE
57430 => // MEDIA_PLAY_PAUSE
57431 => // MEDIA_REVERSE
57432 => // MEDIA_STOP
57433 => // MEDIA_FAST_FORWARD
57434 => // MEDIA_REWIND
57435 => // MEDIA_TRACK_NEXT
57436 => // MEDIA_TRACK_PREVIOUS
57437 => // MEDIA_RECORD
57438 => // LOWER_VOLUME
57439 => // RAISE_VOLUME
57440 => // MUTE_VOLUME
57441 => // LEFT_SHIFT
57442 => // LEFT_CONTROL
57443 => // LEFT_ALT
57444 => // LEFT_SUPER
57445 => // LEFT_HYPER
57446 => // LEFT_META
57447 => // RIGHT_SHIFT
57448 => // RIGHT_CONTROL
57449 => // RIGHT_ALT
57450 => // RIGHT_SUPER
57451 => // RIGHT_HYPER
57452 => // RIGHT_META
57453 => // ISO_LEVEL3_SHIFT
57454 => // ISO_LEVEL5_SHIFT
    }
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
    // TODO: IS THIS SAFE?
    return buff[0..end];
}

/// Handles SS3 Code
/// Must only be called when you know the buff begins with {0x1B,'O'}
fn handleSS3Code(buff: []const u8) !?KeyEvent {
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
        return KeyEvent{ .code = code, .modifier = KeyModifier{} };
    }
}

fn parseUtf8Char(buff: []const u8) !?u21 {
    return std.unicode.utf8Decode(buff) catch {
        const required_bytes: u8 = switch (buff[0]) {
            // https://en.wikipedia.org/wiki/UTF-8#Description
            0x00...0x7F => 1, // 0xxxxxxx
            0xC0...0xDF => 2, // 110xxxxx 10xxxxxx
            0xE0...0xEF => 3, // 1110xxxx 10xxxxxx 10xxxxxx
            0xF0...0xF7 => 4, // 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
            0x80...0xBF, 0xF8...0xFF => return error.UnparseableEvent,
        };

        if (required_bytes > 1 and buff.len > 1) {
            for (buff[1..]) |byte| {
                if (byte & ~@as(u8, 0b0011_1111) != 0b1000_0000) {
                    return error.UnparseableEvent;
                }
            }
        }

        if (buff.len < required_bytes) {
            return null;
        } else {
            return error.UnparseableEvent;
        }
    };
}

inline fn parseModifier(mod: u8) KeyModifier {
    // Kitty protocol, modifier base state is 1, so we need to subract one
    const modifier = mod - 1;
    return @bitCast(modifier);
}

test "parse event 'A'" {
    testing.refAllDecls(@This());
    const res = try parseEvent(&[_]u8{'A'}, false);
    try testing.expect(std.meta.eql(res.?, KeyEvent{ .code = KeyCode{ .Char = 'A' }, .modifier = KeyModifier{} }));
}

test "parse event '󱫎'" {
    testing.refAllDecls(@This());
    const res2 = try parseEvent(&[_]u8{ 0xf3, 0xb1, 0xab, 0x8e }, false);
    try testing.expect(std.meta.eql(res2.?, KeyEvent{ .code = KeyCode{ .Char = '󱫎' }, .modifier = KeyModifier{} }));
}

test "parse escape sequence" {
    const input = "\x1BOD";
    const res = try parseEvent(input[0..], false);
    try testing.expect(std.meta.eql(res.?, KeyEvent{ .code = KeyCode.Left, .modifier = KeyModifier{} }));
}

test "parse csi" {
    const input = [_]u8{ 0x1B, '[', 0x1, ';', 0x2, 'D' };
    const res = try handleCSI(input[0..]);
    try testing.expect(std.meta.eql(res.?, KeyEvent{ .code = KeyCode.Left, .modifier = KeyModifier{ .shift = true } }));
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
        try testing.expect(std.meta.eql(res.?, KeyEvent{ .code = code, .modifier = KeyModifier{} }));
    }
}

test "parse c0 codes to standard representation" {
    // 'Standard' Table can be found here https://vt100.net/docs/vt100-ug/chapter3.html
    const codes = [32]std.meta.Tuple(&.{ u8, KeyEvent }){
        .{ 0, KeyEvent{ .code = KeyCode{ .Char = ' ' }, .modifier = KeyModifier.control() } },
        .{ 1, KeyEvent{ .code = KeyCode{ .Char = 'a' }, .modifier = KeyModifier.control() } },
        .{ 2, KeyEvent{ .code = KeyCode{ .Char = 'b' }, .modifier = KeyModifier.control() } },
        .{ 3, KeyEvent{ .code = KeyCode{ .Char = 'c' }, .modifier = KeyModifier.control() } },
        .{ 4, KeyEvent{ .code = KeyCode{ .Char = 'd' }, .modifier = KeyModifier.control() } },
        .{ 5, KeyEvent{ .code = KeyCode{ .Char = 'e' }, .modifier = KeyModifier.control() } },
        .{ 6, KeyEvent{ .code = KeyCode{ .Char = 'f' }, .modifier = KeyModifier.control() } },
        .{ 7, KeyEvent{ .code = KeyCode{ .Char = 'g' }, .modifier = KeyModifier.control() } },
        .{ 8, KeyEvent{ .code = KeyCode.Backspace, .modifier = KeyModifier.control() } },
        .{ 9, KeyEvent{ .code = KeyCode.Tab, .modifier = KeyModifier{} } },
        .{ 10, KeyEvent{ .code = KeyCode{ .Char = 'j' }, .modifier = KeyModifier.control() } },
        .{ 11, KeyEvent{ .code = KeyCode{ .Char = 'k' }, .modifier = KeyModifier.control() } },
        .{ 12, KeyEvent{ .code = KeyCode{ .Char = 'l' }, .modifier = KeyModifier.control() } },
        .{ 13, KeyEvent{ .code = KeyCode.Enter, .modifier = KeyModifier{} } },
        .{ 14, KeyEvent{ .code = KeyCode{ .Char = 'n' }, .modifier = KeyModifier.control() } },
        .{ 15, KeyEvent{ .code = KeyCode{ .Char = 'o' }, .modifier = KeyModifier.control() } },
        .{ 16, KeyEvent{ .code = KeyCode{ .Char = 'p' }, .modifier = KeyModifier.control() } },
        .{ 17, KeyEvent{ .code = KeyCode{ .Char = 'q' }, .modifier = KeyModifier.control() } },
        .{ 18, KeyEvent{ .code = KeyCode{ .Char = 'r' }, .modifier = KeyModifier.control() } },
        .{ 19, KeyEvent{ .code = KeyCode{ .Char = 's' }, .modifier = KeyModifier.control() } },
        .{ 20, KeyEvent{ .code = KeyCode{ .Char = 't' }, .modifier = KeyModifier.control() } },
        .{ 21, KeyEvent{ .code = KeyCode{ .Char = 'u' }, .modifier = KeyModifier.control() } },
        .{ 22, KeyEvent{ .code = KeyCode{ .Char = 'v' }, .modifier = KeyModifier.control() } },
        .{ 23, KeyEvent{ .code = KeyCode{ .Char = 'w' }, .modifier = KeyModifier.control() } },
        .{ 24, KeyEvent{ .code = KeyCode{ .Char = 'x' }, .modifier = KeyModifier.control() } },
        .{ 25, KeyEvent{ .code = KeyCode{ .Char = 'y' }, .modifier = KeyModifier.control() } },
        .{ 26, KeyEvent{ .code = KeyCode{ .Char = 'z' }, .modifier = KeyModifier.control() } },
        .{ 27, KeyEvent{ .code = KeyCode.Esc, .modifier = KeyModifier{} } },
        .{ 28, KeyEvent{ .code = KeyCode{ .Char = '\\' }, .modifier = KeyModifier.control() } },
        .{ 29, KeyEvent{ .code = KeyCode{ .Char = ']' }, .modifier = KeyModifier.control() } },
        .{ 30, KeyEvent{ .code = KeyCode{ .Char = '~' }, .modifier = KeyModifier.control() } },
        .{ 31, KeyEvent{ .code = KeyCode{ .Char = '?' }, .modifier = KeyModifier.control() } },
    };

    inline for (codes) |code| {
        const result = try parseEvent(&[_]u8{code.@"0"}, false);
        try testing.expect(std.meta.eql(code.@"1", result.?));
    }
}

test "parse Extended Keyboard Events" {
    const result = try parseEvent("\x1b\x5b57428u");
    try testing.expect(std.meta.eql(KeyEvent{ .code = KeyCode{ .Media = .Play }, .modifier = KeyModifier{} }, result.?));
}
