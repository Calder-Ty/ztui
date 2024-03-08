//! Simple tool to echo events
//! Used as an example and to test the event code
const std = @import("std");
const event_reader = @import("events/event_reader.zig");

pub fn main() !void {
    std.debug.print("Please type some input...\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const flags = event_reader.ProgressiveEnhancements{ .disambiguate_escape_codes = true };
    try event_reader.pushProgressiveEnhancements(flags);
    defer event_reader.popProgressiveEnhancements() catch {}; // UH-OH
    const allocator = gpa.allocator();
    for (0..10) |_| {
        var reader = event_reader.EventReader.init();
        if (try reader.poll(allocator)) {
            while (reader.next(allocator, true)) |event| {
                std.debug.print("Event: {?}\n", .{event});
            }
        }
    }
}