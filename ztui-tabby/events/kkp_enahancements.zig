const std = @import("std");

/// Value to push on to stack to request Progressive enhancements of
/// keyboard protocol, from simply legacy to adding more KKP features.
///
/// Should be pushed onto terminal stack at the beginning of program
/// and popped off of stack at end of program.
pub const ProgressiveEnhancements = packed struct(u8) {
    /// Fix the problem that some legacy key press encodings overlap
    /// with other control codes. (eg `Esc` and the first byte of an escape code)
    disambiguate_escape_codes: bool = false,
    /// Report the event type (press, release, hold).
    report_event_types: bool = false,
    /// Report alternate keys (such as A when <S-a> is pressed)
    report_alternate_keys: bool = false,
    /// No naked text will be sent, all key presses will be reported as escape
    /// codes, including Enter, Tab, and Backspace
    report_all_keys_as_escapecodes: bool = false,
    // Currently Reporting associated text is not a supported enhancement by the library.
    // We reserve 4 bits as a placeholder for it (and remaining 3 bits).
    // report_associated_text: bool,
    _reserved: u4 = 0,

    /// Generate the Keyboard Enhancement bitfield from a string
    /// representation of the field.
    pub fn from_str(str: []const u8) !ProgressiveEnhancements {
        const val = std.fmt.parseInt(u8, str, 0) catch {
            return error.InvalidProgressiveEnhancementValue;
        };
        return @bitCast(val);
    }
};

test "from_str_dec" {
    const expected: ProgressiveEnhancements = .{};
    try std.testing.expectEqual(expected, ProgressiveEnhancements.from_str("0"));
}

test "from_str_hex" {
    const expected: ProgressiveEnhancements = .{};
    try std.testing.expectEqual(expected, ProgressiveEnhancements.from_str("0x0"));
}

test "from_str_octal" {
    const expected: ProgressiveEnhancements = .{};
    try std.testing.expectEqual(expected, ProgressiveEnhancements.from_str("0o0"));
}

test "from_str_binary" {
    const expected: ProgressiveEnhancements = .{};
    try std.testing.expectEqual(expected, ProgressiveEnhancements.from_str("0b0"));
}

test "from_str_binary2" {
    const expected: ProgressiveEnhancements = .{
        .disambiguate_escape_codes = true,
        .report_alternate_keys = true,
    };
    try std.testing.expectEqual(expected, ProgressiveEnhancements.from_str("0b101"));
}
