const std = @import("std");
const ztui = @import("ztui");
const keycodes = ztui.event_reader.keycodes;

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

    try ztui.terminal.enableRawMode();
    defer ztui.terminal.disableRawMode() catch {}; // UH-OH

    while (true) {
        // This _IS_ reading stdin, because when I press keys
        // it reads and then stops (because the producer thread is done)
        const res = try ztui.event_reader.read(allocator);
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
