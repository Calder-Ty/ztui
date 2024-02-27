// Example app
const std = @import("std");
const ztui = @import("ztui");

pub fn main() !void {
    const term = try ztui.terminal.Terminal.init();
    defer term.deinit();
    std.time.sleep(2_000_000_000);
    const res = try ztui.EventReader.poll(100);
    std.debug.print("We gotem!", .{});
    std.debug.print("text: {s}", .{res[0][0..res[1]]});
    std.time.sleep(2_000_000_000);
}
