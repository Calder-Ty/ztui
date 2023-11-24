//! Handle Keyboard Events
//! Much inspiration taken from Crosterm-rs
const std = @import("std");
const keycodes = @import("./keyevents.zig");
const io = std.io;
const fs = std.fs;

const READER_BUF_SIZE = 1024;

const ReadOut = struct { [READER_BUF_SIZE]u8, usize };

/// Read Input and generate an Event stream
pub const EventReader = struct {
    allocator: std.mem.Allocator,
    event_channel: std.event.Channel(keycodes.KeyCode),

    pub fn init(allocator: std.mem.Allocator) EventReader {
        var event_buffer = std.RingBuffer.init(allocator, READER_BUF_SIZE * 4)
        return EventReader{ .allocator = allocator };
    }

    // Read values from stdin
    pub fn read() !ReadOut {
        var inbuff = [_]u8{0} ** READER_BUF_SIZE;
        const stdin = io.getStdIn();
        const n = try stdin.read(&inbuff);
        return .{ inbuff, n };
    }

    fn name_the_func(inbuff: []u8, more: bool) {
        var start = 0;
        for (inbuff, 1..) |byte, i| {
            more_available = i < inbuff.len or more;

            offset = i - start;

            const res = parse_event(inbuff[start..start+offset], more) catch {
                start = i - 1;
                continue;
            };

            if (res) 


        }

    }


    fn parse_event(parse_buffer: []u8, more: bool) !?keycodes.KeyCode {
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
                                        return keycodes.KeyCode.F(1 + val - 'P');
                                    },
                                    else => return error.CouldNotParse,
                                }
                            }
                        },
                        // '[' => parse_csi(parse_buffer),
                        '\x1B' => return keycodes.keycodes.Esc,
                        // Not doing public events right now
                        else => {},
                    }
                }
            },
            '\r' => return keycodes.KeyCode.Enter,
            // '\n' We need to hanlde this.
            '\t' => return keycodes.KeyCode.Tab,
            0x7F => keycodes.KeyCode.Backspace,
            0x01...0x1A => |c| keycodes.KeyCode.Char((c - 0x1 + 'a')),
            else => {
                // Not really, just unimplemented for now
                unreachable;
            },
        }
    }
};
