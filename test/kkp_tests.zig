const testing = @import("std").testing;
const ztui = @import("../src/root.zig");
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
inline for @Type(keycodes.KeyCodeTags) {
}
