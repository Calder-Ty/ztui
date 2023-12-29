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

fn parseEvent(parse_buffer: []const u8, more: bool) !?keycodes.KeyCode {
    switch (parse_buffer[0]) {
        0x1B => {
            if (parse_buffer.len == 1) {
                if (more) {
                    // Possible Esc sequence
                    return null;
                } else {
                    return keycodes.KeyCode.Esc;
                }
            } else {
                switch (parse_buffer[1]) {
                    'O' => {
                        if (parse_buffer.len == 2) {
                            return null;
                        } else {
                            switch (parse_buffer[2]) {
                                'D' => return keycodes.KeyCode.Left,
                                'C' => return keycodes.KeyCode.Right,
                                'A' => return keycodes.KeyCode.Up,
                                'B' => return keycodes.KeyCode.Down,
                                'H' => return keycodes.KeyCode.Home,
                                'F' => return keycodes.KeyCode.End,
                                // F1-F4
                                'P'...'S' => |val| {
                                    return keycodes.KeyCode{ .F = (1 + val - 'P') };
                                },
                                else => return error.CouldNotParse,
                            }
                        }
                    },
                    // '[' => parse_csi(parse_buffer),
                    0x1B => return keycodes.KeyCode.Esc,
                    // Not doing public events right now
                    else => {
                        return null;
                    },
                }
            }
        },
        '\r' => return keycodes.KeyCode.Enter,
        // '\n' We need to hanlde this.
        '\t' => return keycodes.KeyCode.Tab,

        0x7F => return keycodes.KeyCode.Backspace,
        // These are Control - Characters.
        // 0x01...0x08, 0x0A...0x0C, 0x0E...0x1A => |c| keycodes.KeyCode.Char((c - 0x1 + 'a')),
        else => {
            // Not unreachable, this will break on any regular text input
            const char = try parseUtf8Char(parse_buffer);
            if (char) |c| {
                return keycodes.KeyCode{ .Char = c };
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
            0x80...0xBF, 0xF8...0xFF => return error.UnparseableCharacter,
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

test "parse event" {
    testing.refAllDecls(@This());
    const res = try parseEvent(&[_]u8{'A'}, false);
    try testing.expect(std.meta.eql(res.?, keycodes.KeyCode{ .Char = 'A' }));
    const res2 = try parseEvent(&[_]u8{ 0xf3, 0xb1, 0xab, 0x8e }, false);
    try testing.expect(std.meta.eql(res2.?, keycodes.KeyCode{ .Char = '󱫎' }));
}

test "parse escape sequence" {
    const input = "\x1BOD";
    const res = try parseEvent(input[0..], false);
    try testing.expect(std.meta.eql(res.?, keycodes.KeyCode.Left));
}
