# Tabby

> “Alice asked the Cheshire Cat, who was sitting in a tree, “What road do I take?”
>
> The cat asked, “Where do you want to go?”
>
> “I don’t know,” Alice answered.
>
> “Then,” said the cat, “it really doesn’t matter, does it?”
>
> ~ Lewis Carroll, Alice's Adventures In Wonderland

Tabby is a Keyboard Event handling library, primarily for use in terminal user interfaces (TUI's).


## Example
```zig
const std = @import("std");
const ztui = @import("ztui");
const keycodes = ztui.event_reader.keycodes;


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
        const res = try ztui.event_reader.read(allocator);
        defer res.deinit();
        for (res.items) |event| {
            std.debug.print("{any}", .{event});
            switch (event.code) {
                .Char => |char| {
                    // Quit on `q`
                    if (char == 'q') {
                        return;
                    }
                },
                else => {},
            }
        }
    }
}
```
