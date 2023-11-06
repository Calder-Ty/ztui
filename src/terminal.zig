//! Start a Terminal for drawing
//!
const std = @import("std");
const fs = std.fs;

const c = @cImport(@cInclude("termios.h"));

const TerminalErrors = error{ ClearScreenFailure, GetTermiosAttrError, SetTermiosAttrError };

pub const Terminal = struct {
    fh: fs.File,
    // TODO: What if we want to do this in a threaded environment? Let's make this threadsafe
    orig_termios: ?c.termios = null,

    pub fn init() !@This() {
        // Get Control of Terminal
        const fh = try fs.openFileAbsolute("/dev/tty", .{
            .mode = .read_write,
            .allow_ctty = true,
        });
        // Clear Screen
        // FIXME: Handle Errors
        try alt_screen(&fh);
        errdefer orig_screen(&fh);
        var term: Terminal = Terminal{ .fh = fh };
        try term.enable_raw_mode();
        return term;
    }

    pub fn deinit(self: Terminal) void {
        // Reset Screen
        self.disable_raw_mode() catch {
            //XXX: Handle this properly?
        };
        orig_screen(&self.fh);
        self.fh.close();
    }

    /// Put the Terminal into "Raw" mode where key input isn't sent to Screen
    /// and line breaks aren't handled. See crosterm-rs and `man termios` for more info
    fn enable_raw_mode(self: *Terminal) !void {
        if (self.orig_termios) |_| {
            return;
        }

        var ios: c.termios = undefined;
        try wrap_as_error_union(c.tcgetattr(self.fh.handle, &ios), TerminalErrors.GetTermiosAttrError);
        const orig = ios;

        c.cfmakeraw(&ios);
        try wrap_as_error_union(c.tcsetattr(self.fh.handle, c.TCSANOW, &ios), TerminalErrors.SetTermiosAttrError);

        self.orig_termios = orig;
    }

    fn disable_raw_mode(self: *const Terminal) !void {
        if (self.orig_termios) |orig_ios| {
            try wrap_as_error_union(c.tcsetattr(self.fh.handle, c.TCSANOW, &orig_ios), TerminalErrors.SetTermiosAttrError);
        }
    }
};

fn alt_screen(fh: *const fs.File) !void {
    _ = try fh.write("\x1B[?1049h");
}

fn orig_screen(fh: *const fs.File) void {
    _ = fh.write("\x1B[?1049l") catch {};
}

fn wrap_as_error_union(return_no: i32, comptime ERROR_VARIANT: TerminalErrors) !void {
    if (return_no == -1) {
        return ERROR_VARIANT;
    }
}
