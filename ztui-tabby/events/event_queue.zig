//! A Custom Event Queue
const std = @import("std");
const testing = std.testing;

pub const Error = error{
    BufferFull,
    InsufficientSpace,
};

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

        /// Pushes a buffer into the RingBuffer. Fails with InsufficentSpace error if
        /// there is not enough room to accommodate whole buffer.
        pub fn pushBuffer(self: *Self, source: []const T) !void {
            if (source.len > self.buffer.len - self.count) {
                return Error.InsufficientSpace;
            }
            // TODO: Mayhaps this is faster with @memcpy, but we need to check
            for (source) |item| {
                try self.push(item);
            }
        }

        /// Peek at the next `n` values in the buffer. if `n` is greater than count, then
        /// just peeks the next valid values. Panics if `dest` length is < n.
        pub fn peekN(self: *Self, n: usize, dest: []T) void {
            if (n > dest.len) {
                @panic("cannot peek for size `n`, when destination slice is smaller than `n`");
            }
            const tail_count = self.buffer.len - self.start;
            if (n > tail_count) {
                @memcpy(dest[0..tail_count], self.buffer[self.start..]);
                @memcpy(dest[tail_count..n], self.buffer[0..(n - tail_count)]);
            }
        }
    };
}

test "Push value" {
    var test_rb = RingBuffer(u8, 8).init();
    try test_rb.push(255);
    try testing.expect(test_rb.buffer[0] == 255);
}

test "test pushBuffer" {
    var test_rb = RingBuffer(u8, 8).init();
    const inbuff = [_]u8{ 1, 2, 3, 4, 5 };
    try test_rb.pushBuffer(&inbuff);
    var i: usize = 0;
    while (test_rb.pop()) |item| {
        try testing.expect(item == inbuff[i]);
        i += 1;
    }
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
