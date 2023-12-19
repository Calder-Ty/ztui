//! A Custom Event Queue
const std = @import("std");
const testing = std.testing;

pub const Error = error{BufferFull};

pub fn RingBuffer(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = @This();
        buffer: [size]?T,
        start: usize = 0,
        count: usize = 0,

        pub fn init() Self {
            const buff = [_]?T{null} ** size;
            return Self{
                .buffer = buff,
            };
        }

        /// Push an Item of Type T onto the buffer
        pub fn push(self: *Self, item: T) !void {
            const next_i = try self.next_index();
            self.buffer[next_i] = item;
            self.count += 1;
        }

        /// Generate the Next Index. Does bounds checking and wraps around
        fn next_index(self: *Self) !usize {
            var next_val: usize = undefined;
            if (self.count + 1 > size) {
                return Error.BufferFull;
            }
            // Loop around
            if (self.start + self.count >= size) {
                next_val = self.start + self.count - size;
            } else {
                next_val = self.start + self.count;
            }
            return next_val;
        }

        /// Pop an Item out an optional T
        pub fn pop(self: *Self) ?T {
            if (self.count == 0) {
                // Empty
                return null;
            }

            const res = self.buffer[self.start];
            if (self.start == size) {
                self.*.start = 0;
            } else {
                self.*.start += 1;
            }
            self.count -= 1;
            return res;
        }
    };
}

test "Push value" {
    var test_rb = RingBuffer(u8, 8).init();
    try test_rb.push(255);
    try testing.expect(test_rb.buffer[0] == 255);
}

test "Pop value" {
    var test_rb = RingBuffer(u8, 8).init();
    try test_rb.push(255);
    _ = test_rb.pop();
    try testing.expect(test_rb.start == 1);
}

test "Push/Pop many values" {
    var test_rb = RingBuffer(u8, 8).init();
    try test_rb.push(255);
    try test_rb.push(255);
    _ = test_rb.pop();
    _ = test_rb.pop();
    try test_rb.push(255);
    try test_rb.push(255);
    try test_rb.push(255);
    try test_rb.push(255);
    try test_rb.push(255);
    try test_rb.push(255);
    try test_rb.push(255);
    try testing.expect(test_rb.start == 2);
    try testing.expect(try test_rb.next_index() == 1);
}
