const std = @import("std");
const testing = std.testing;
const ztui = @import("ztui");
const keycodes = ztui.event_reader.keycodes;
const Thread = std.Thread;

const c = @cImport(@cInclude("termios.h"));

var _END_WRITE_MUTEX: Thread.Mutex = .{};
var _END_WRITE: bool = false;

// Ensure that all keys are emitted as expected when
// written to the output
test "Full Table Suite" {
    try testing.expect(true);
}

const TableRecord = struct { bytes: []const u8, result: ztui.event_reader.keycodes.KeyEvent };

const TestTable = [_]TableRecord{};

// Generate the table from a file
// Loop over every key, event and build out a set of bytes that _should_ generate that event
//
// generate by writing out the bytes of codes and then validating that we get stuff?

// first lets embed the file we are going to use to generate events
const event_text = @embedFile("./test_events");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const status = gpa.deinit();
        if (status == .leak) @panic("Memory Leak Occured");
    }
    try ztui.terminal.enableRawMode();
    defer ztui.terminal.disableRawMode() catch {}; // UH-OH

    var results = std.ArrayList(ztui.event_reader.keycodes.KeyEvent).init(allocator);
    defer results.deinit();

    std.debug.print("Ready to read\n", .{});
    while (true) {
        // This _IS_ reading stdin, because when I press keys
        // it reads and then stops (because the producer thread is done)
        const res = try ztui.event_reader.read(allocator);
        defer res.deinit();
        for (res.items) |event| {
            switch (event.code) {
                .Char => |char| {
                    if (char == 113) {
                        std.debug.print("Quitting", .{});
                        return;
                    } else {
                        std.debug.print("{any}", .{event});
                    }
                },
                else => {
                    std.debug.print("{any}", .{event});
                },
            }
        }
    }
}
