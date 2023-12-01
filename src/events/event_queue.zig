//! A Custom Event Queue
const std = @import("std");
const testing = std.testing;

pub const Error = error{BufferFull};

fn GenericRingBuffer(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = @This();
        buffer: [size]?T,
        start: usize,
        end: usize,

        pub fn init() Self {
            const buff = [_]?T{null} ** size;
            return Self{
                .buffer = buff,
                .start = 0,
                .end = 0,
            };
        }

        /// Push an Item of Type T onto the buffer
        pub fn push(self: *Self, item: T) !void {
            const next_i = self.next_index();
            // Check Buffer is not full
            if (self.start == next_i) {
                return Error.BufferFull;
            }
            self.buffer[next_i] = item;
            self.end += 1;
        }

        fn next_index(self: *Self) usize {
            if (self.end == size - 1) {
                return 0;
            }
            return self.end + 1;
        }

        /// Pop an Item out an optional T
        pub fn pop(self: *Self) !?T {
            if (self.end == self.start) {
                // Empty
                return null;
            }
        }
    };
}

test "Push value" {
    var test_rb = GenericRingBuffer(u8, 8).init();
    try test_rb.push(255);
    try testing.expect(test_rb.buffer[0] == 255);
}
