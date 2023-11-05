//! Start a Terminal for drawing
//!
const std = @import("std");
const fs = std.fs;

pub const Terminal = struct {
    fh: fs.File,

    pub fn init() @This() {
        // Open a New Terminal
        fs.openAbsolute();
    }
};
