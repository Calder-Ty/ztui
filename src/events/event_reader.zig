//! Handle Keyboard Events
//! Much inspiration taken from Crosterm-rs
const std = @import("std");
const keycodes = @import("keyevents.zig");
const event_queue = @import("event_queue.zig");
const testing = std.testing;
const io = std.io;
const fs = std.fs;

const READER_BUF_SIZE = 1024;

const ReadOut = struct { [READER_BUF_SIZE]u8, usize };

/// Read Input and generate an Event stream
pub const EventReader = struct {
    event_buffer: event_queue.RingBuffer(keycodes.KeyCode, READER_BUF_SIZE),

    pub fn init() EventReader {
        const event_buffer = event_queue.RingBuffer(keycodes.KeyCode, READER_BUF_SIZE).init();
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

            const res = parseEvent(inbuff[start .. start + offset], more) catch {
                start = i - 1;
                continue;
            };
            _ = res;
        }
    }
};

fn parseEvent(parse_buffer: []const u8, more: bool) !?keycodes.KeyEvent {
    switch (parse_buffer[0]) {
        // | `ESC` | 27      | 033   | 0x1B | `\e`[*](#escape) | `^[` | Escape character           |
        0x1B => {
            if (parse_buffer.len == 1) {
                if (more) {
                    // Possible Esc sequence
                    return null;
                } else {
                    return keycodes.KeyEvent{
                        .code = keycodes.KeyCode.Esc,
                        .modifier = keycodes.KeyModifier{},
                    };
                }
            } else {
                const code: keycodes.KeyCode = switch (parse_buffer[1]) {
                    'O' => blk: {
                        if (parse_buffer.len == 2) {
                            return null;
                        } else {
                            switch (parse_buffer[2]) {
                                'A' => break :blk keycodes.KeyCode.Up,
                                'B' => break :blk keycodes.KeyCode.Down,
                                'C' => break :blk keycodes.KeyCode.Right,
                                'D' => break :blk keycodes.KeyCode.Left,
                                'H' => break :blk keycodes.KeyCode.Home,
                                'F' => break :blk keycodes.KeyCode.End,
                                // F1-F4
                                'P'...'S' => |val| {
                                    break :blk keycodes.KeyCode{ .F = (1 + val - 'P') };
                                },
                                else => return error.CouldNotParse,
                            }
                        }
                    },
                    // '[' => parse_csi(parse_buffer),
                    0x1B => keycodes.KeyCode.Esc,
                    // Not doing public events right now
                    else => {
                        return null;
                    },
                };
                return keycodes.KeyEvent{ .code = code, .modifier = keycodes.KeyModifier{} };
            }
        },
        '\r' => return keycodes.KeyEvent{ .code = keycodes.KeyCode.Enter, .modifier = keycodes.KeyModifier{} },
        // '\n' We need to hanlde this.
        '\t' => return keycodes.KeyEvent{ .code = keycodes.KeyCode.Tab, .modifier = keycodes.KeyModifier{} },

        // | `DEL` | 127     | 177   | 0x7F | `<none>` | `<none>` | Delete character               |
        0x7F => return keycodes.KeyEvent{ .code = keycodes.KeyCode.Delete, .modifier = keycodes.KeyModifier{} },
        // These are Control - Characters.
        // | `BS`  | 8       | 010   | 0x08 | `\b`     | `^H`     | Backspace                      |
        0x08 => return keycodes.KeyEvent{ .code = keycodes.KeyCode.Backspace, .modifier = keycodes.KeyModifier{} },
        0x01...0x07, 0x0A...0x0C, 0x0E...0x1A => |c| {
            return keycodes.KeyEvent{
                .code = keycodes.KeyCode{ .Char = (c - 0x1 + 'a') },
                .modifier = keycodes.KeyModifier.control(),
            };
        },
        0x1C...0x1F => |c| {
            return keycodes.KeyEvent{
                .code = keycodes.KeyCode{ .Char = (c - 0x1 + '4') },
                .modifier = keycodes.KeyModifier.control(),
            };
        },
        0x0 => return keycodes.KeyEvent{
            .code = keycodes.KeyCode{ .Char = ' ' },
            .modifier = keycodes.KeyModifier.control(),
        },
        else => {
            // Not unreachable, this will break on any regular text input
            const char = try parseUtf8Char(parse_buffer);
            if (char) |c| {
                return keycodes.KeyEvent{ .code = keycodes.KeyCode{ .Char = c }, .modifier = keycodes.KeyModifier{} };
            }
            return null;
        },
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
    try testing.expect(std.meta.eql(res.?, keycodes.KeyEvent{ .code = keycodes.KeyCode{ .Char = 'A' }, .modifier = keycodes.KeyModifier{} }));
}

test "parse event '󱫎'" {
    testing.refAllDecls(@This());
    const res2 = try parseEvent(&[_]u8{ 0xf3, 0xb1, 0xab, 0x8e }, false);
    try testing.expect(std.meta.eql(res2.?, keycodes.KeyEvent{ .code = keycodes.KeyCode{ .Char = '󱫎' }, .modifier = keycodes.KeyModifier{} }));
}

test "parse escape sequence" {
    const input = "\x1BOD";
    const res = try parseEvent(input[0..], false);
    try testing.expect(std.meta.eql(res.?, keycodes.KeyEvent{ .code = keycodes.KeyCode.Left, .modifier = keycodes.KeyModifier{} }));
}
