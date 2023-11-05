//! Start a Terminal for drawing
//!
const std = @import("std");
const fs = std.fs;

pub const Terminal = struct {
    fh: fs.File,

    pub fn init() !@This() {
        // Get Control of Terminal
        const fh = try fs.openFileAbsolute("/dev/tty", .{
            .mode = .read_write,
            .allow_ctty = true,
        });
        // Clear Screen
        _ = try fh.write("\x1B[?1049h");
        return Terminal{ .fh = fh };
    }

    pub fn deinit(self: Terminal) void {
        // Reset Screen
        _ = self.fh.write("\x1B[?1049l") catch {};
        self.fh.close();
    }
};
