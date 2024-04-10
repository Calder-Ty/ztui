const std = @import("std");
const testing = std.testing;
pub const terminal = @import("terminal.zig");
pub const event_reader = @import("events/event_reader.zig");

test "Run Tests" {
    testing.refAllDecls(@This());
}
