const std = @import("std");
const testing = std.testing;
pub const terminal = @import("./terminal.zig");
pub const EventReader = @import("./events/event_reader.zig").EventReader;

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}
