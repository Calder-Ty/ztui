const std = @import("std");
const tabby = @import("tabby");
const keycodes = tabby.event_reader.keycodes;

// Generate the table from a file
// Loop over every key, event and build out a set of bytes that _should_ generate that event
//
// generate by writing out the bytes of codes and then validating that we get stuff?
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const status = gpa.deinit();
        if (status == .leak) @panic("Memory Leak Occured");
    }

    try tabby.terminal.enableRawMode();
    defer tabby.terminal.disableRawMode() catch {}; // UH-OH

    while (true) {
        const res = try tabby.event_reader.read(allocator);
        defer res.deinit();
        for (res.items) |event| {
            std.debug.print("{any}", .{event});
            switch (event.code) {
                .Char => |char| {
                    if (char == 113) {
                        return;
                    }
                },
                else => {},
            }
        }
    }
}
