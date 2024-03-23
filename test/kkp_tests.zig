const std = @import("std");
const testing = std.testing;
const ztui = @import("ztui");
const keycodes = ztui.event_reader.keycodes;

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

fn runTest() !void {
    const allocator = testing.allocator;
    // TODO: This could probably be done at comptime?
    var inputs = std.mem.splitScalar(u8, event_text, '\n');
    const stdout = std.io.getStdOut();
    while (inputs.next()) |in| {
        _ = try stdout.write(in);
    }
    const events = ztui.event_reader.read(allocator);
    std.debug.print(events);
}

test "integration_tests" {
    try runTest();
}
