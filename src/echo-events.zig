//! Simple tool to echo events
//! Used as an example and to test the event code
const std = @import("std");
const terminal = @import("terminal.zig");
const event_reader = @import("events/event_reader.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const flags = event_reader.ProgressiveEnhancements{ .disambiguate_escape_codes = true };
    try terminal.enableRawMode();
    defer terminal.disableRawMode() catch {}; // UH-OH

    try event_reader.pushProgressiveEnhancements(flags);
    defer event_reader.popProgressiveEnhancements() catch {}; // UH-OH

    const allocator = gpa.allocator();
    if (try event_reader.detectProgressivEnhancementSupport(allocator)) {
        std.debug.print("ProgressiveEnhancements Supported in terminal\n", .{});
    }
    std.debug.print("Please type some input...\n", .{});
    for (0..10) |_| {
        var events = try event_reader.read(allocator);
        defer events.deinit();
        for (events.items) |event| {
            std.debug.print("Event: {?}\n", .{event});
        }
    }
}
