const std = @import("std");
const testing = std.testing;
pub const terminal = @import("terminal.zig");
pub const event_queue = @import("events/event_queue.zig");
pub const event_reader = @import("events/event_reader.zig");

test "basic add functionality" {
    testing.refAllDecls(@This());
}
