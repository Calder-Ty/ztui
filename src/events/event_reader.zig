//! Handle Keyboard Events
//! Much inspiration taken from Crosterm-rs
const std = @import("std");
const keycodes = @import("./keyevents.zig");
const event_queue = @import("./event_queue.zig");
const testing = std.testing;
const io = std.io;
const fs = std.fs;

const READER_BUF_SIZE = 1024;

const ReadOut = struct { [READER_BUF_SIZE]u8, usize };

/// Read Input and generate an Event stream
pub const EventReader = struct {
    event_buffer: event_queue.RingBuffer(keycodes.KeyCode, READER_BUF_SIZE),

    pub fn init() EventReader {
        var event_buffer = event_queue.RingBuffer(keycodes.KeyCode, READER_BUF_SIZE).init();
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

            const res = parse_event(inbuff[start .. start + offset], more) catch {
                start = i - 1;
                continue;
            };
            _ = res;
        }
    }
};

fn parse_event(parse_buffer: []const u8, more: bool) !?keycodes.KeyCode {
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
            // Not really, just unimplemented for now
            unreachable;
        },
    }
}

test "parse event" {
    testing.refAllDecls(@This());
    const input = [_]u8{ 'A', 'B', 'C' };
    const res = try parse_event(input[0..], false);
    try testing.expect(std.meta.eql(res.?, keycodes.KeyCode{ .Char = 'A' }));
}
