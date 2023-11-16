// Example app
const std = @import("std");
const ztui = @import("ztui");

pub fn main() !void {
    const term = try ztui.terminal.Terminal.init();
    defer term.deinit();
    std.time.sleep(2_000_000_000);
}
