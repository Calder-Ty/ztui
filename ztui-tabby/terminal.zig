//! Provides utilities for managing the terminal, such as putting it into "Raw Mode"
//!
const std = @import("std");
const fs = std.fs;
const Mutex = std.Thread.Mutex;

const c = @cImport(@cInclude("termios.h"));

const TerminalErrors = error{ ClearScreenFailure, GetTermiosAttrError, SetTermiosAttrError };

const OrigTermiosMutex = struct {
    mutex: Mutex = Mutex{},
    _orig_termios: ?c.termios = null,

    inline fn lock(self: *OrigTermiosMutex) *?c.termios {
        self.mutex.lock();
        return &self._orig_termios;
    }

    inline fn unlock(self: *OrigTermiosMutex) void {
        self.mutex.unlock();
    }
};

var orig_termios_mutex = OrigTermiosMutex{};

/// Put the Terminal into "Raw" mode where key input isn't sent to Screen
/// and line breaks aren't handled. See `man termios` for more info
pub fn enableRawMode() !void {
    const fh = try fs.openFileAbsolute("/dev/tty", .{
        .mode = .read_write,
        .allow_ctty = true,
    });
    const orig_termios = orig_termios_mutex.lock();
    defer orig_termios_mutex.unlock();
    if (orig_termios.*) |_| {
        return;
    }

    var ios: c.termios = undefined;
    try wrapAsErrorUnion(c.tcgetattr(fh.handle, &ios), TerminalErrors.GetTermiosAttrError);
    const orig = ios;

    c.cfmakeraw(&ios);
    try wrapAsErrorUnion(c.tcsetattr(fh.handle, c.TCSANOW, &ios), TerminalErrors.SetTermiosAttrError);

    // Set the orig_termios if needed
    orig_termios.* = orig;
}

/// Release Terminal from "Raw" mode. See `man termios` for more information on
/// RawMode
pub fn disableRawMode() !void {
    const fh = try fs.openFileAbsolute("/dev/tty", .{
        .mode = .read_write,
        .allow_ctty = true,
    });
    const orig_termios = orig_termios_mutex.lock();
    defer orig_termios_mutex.unlock();
    if (orig_termios.*) |orig_ios| {
        try wrapAsErrorUnion(c.tcsetattr(fh.handle, c.TCSANOW, &orig_ios), TerminalErrors.SetTermiosAttrError);
    }
}

/// Sends sequence of commands to terminal to put it into an alternate screen
pub fn altScreen() !void {
    const fh = try fs.openFileAbsolute("/dev/tty", .{
        .mode = .read_write,
        .allow_ctty = true,
    });
    _ = try fh.write("\x1B[?1049h");
}

/// Sends sequence of commands to terminal to pop the alternate screen and return
/// to the original
pub fn origScreen() !void {
    const fh = try fs.openFileAbsolute("/dev/tty", .{
        .mode = .read_write,
        .allow_ctty = true,
    });
    _ = fh.write("\x1B[?1049l") catch {};
}

fn wrapAsErrorUnion(return_no: i32, comptime ERROR_VARIANT: TerminalErrors) !void {
    if (return_no == -1) {
        return ERROR_VARIANT;
    }
}
