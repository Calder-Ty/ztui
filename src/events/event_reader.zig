//! Handle Keyboard Events using the [Kitty Keyboard protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/#functional).
//! Much of the implementation is translated from Crosterm-rs
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

    // # For Legacy Encoding there are 3 big things that we want to make sure
    // SI number ; modifier ~
    // CSI 1 ; modifier {ABCDEFHPQS}
    switch (parse_buffer[0]) {
        // | `ESC` | 27      | 033   | 0x1B | `\e`[*](#escape) | `^[` | Escape character           |
        0x1B => {
            if (parse_buffer.len == 1) {
                if (more) {
                    // Possible Esc sequence
                    return null;
                } else {
                    return KeyEvent{
                        .code = KeyCode.Esc,
                        .modifier = KeyModifier{},
                    };
                }
            } else {
                return switch (parse_buffer[1]) {
                    // SS3 {ABCDEFHPQRS}
                    'O' => try handleSS3Code(parse_buffer),
                    '[' => handleCSI(parse_buffer),
                    0x1B => KeyEvent{ .code = KeyCode.Esc, .modifier = KeyModifier{} },
                    // Not doing public events right now
                    else => {
                        return null;
                    },
                };
            }
        },
        '\r' => return KeyEvent{ .code = KeyCode.Enter, .modifier = KeyModifier{} },
        // FIXME: This needs special care for when we are in RAW MODE, which is kinda always
        // '\n' We need to hanlde this.
        '\t' => return KeyEvent{ .code = KeyCode.Tab, .modifier = KeyModifier{} },

        // Kity Has this as Backspace
        0x7F => return KeyEvent{ .code = KeyCode.Backspace, .modifier = KeyModifier{} },
        // These are Control - Characters.
        // | `BS`  | 8       | 010   | 0x08 | `\b`     | `^H`     | Backspace                      |
        0x08 => return KeyEvent{ .code = KeyCode.Backspace, .modifier = KeyModifier.control() },
        0x01...0x07, 0x0A...0x0C, 0x0E...0x1A => |c| {
            return KeyEvent{
                .code = KeyCode{ .Char = (c - 0x1 + 'a') },
                .modifier = KeyModifier.control(),
            };
        },
        0x1C...0x1F => |c| {
            return KeyEvent{
                .code = KeyCode{ .Char = (c - 0x1 + '4') },
                .modifier = KeyModifier.control(),
            };
        },
        0x0 => return KeyEvent{
            .code = KeyCode{ .Char = ' ' },
            .modifier = KeyModifier.control(),
        },
        else => {
            // Not unreachable, this will break on any regular text input
            const char = try parseUtf8Char(parse_buffer);
            if (char) |c| {
                return KeyEvent{ .code = KeyCode{ .Char = c }, .modifier = KeyModifier{} };
            }
            return null;
        },
    }
}

fn handleCSI(buff: []const u8) ?KeyEvent {
    std.debug.assert(std.mem.eql(u8, buff[0..2], &[_]u8{ 0x1B, '[' }));

    if (buff.len == 2) {
        return null;
    }

    return switch (buff[2]) {
        'A' => KeyEvent{ .code = KeyCode.Up, .modifier = KeyModifier{} },
        'B' => KeyEvent{ .code = KeyCode.Down, .modifier = KeyModifier{} },
        'C' => KeyEvent{ .code = KeyCode.Right, .modifier = KeyModifier{} },
        'D' => KeyEvent{ .code = KeyCode.Left, .modifier = KeyModifier{} },
        'H' => KeyEvent{ .code = KeyCode.Home, .modifier = KeyModifier{} },
        'F' => KeyEvent{ .code = KeyCode.End, .modifier = KeyModifier{} },
        else => null,
    };
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
    const input = [_]u8{ 0x1B, '[', 'D' };
    const res = handleCSI(input[0..]);
    try testing.expect(std.meta.eql(res.?, KeyEvent{ .code = KeyCode.Left, .modifier = KeyModifier{} }));
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
