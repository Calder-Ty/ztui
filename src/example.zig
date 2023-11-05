// Example app
const std = @import("std");
const ztui = @import("./terminal.zig");

pub fn main() !void {
    const term = try ztui.Terminal.init();
    defer term.deinit();
    std.time.sleep(1_000_000_000);
}
