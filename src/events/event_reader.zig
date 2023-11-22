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

    pub fn init(allocator: std.mem.Allocator) EventReader {
        return EventReader{ .allocator = allocator };
    }

    // Read values from stdin
    pub fn read() !ReadOut {
        var inbuff = [_]u8{0} ** READER_BUF_SIZE;
        const stdin = io.getStdIn();
        const n = try stdin.read(&inbuff);
        return .{ inbuff, n };
    }

    fn parse_event() keycodes.KeyCode {}
};
