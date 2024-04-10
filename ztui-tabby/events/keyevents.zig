//! Handle Keyboard Events
//! Much inspiration taken from Crosterm-rs
const std = @import("std");

/// Represents the keypress action that triggered the event.
/// press is always reported unless `report_event_types`
/// progressive enhancement is activated.
pub const KeyAction = enum(u2) {
    press = 1,
    repeat,
    release,
};

/// Field that displays what modifiers were pressed along with the event.
pub const KeyModifier = packed struct(u8) {
    shift: bool = false,
    alt: bool = false,
    control: bool = false,
    super: bool = false,
    hyper: bool = false,
    meta: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,

    /// Convinence function for generating a shift modifier
    pub fn shift() KeyModifier {
        return KeyModifier{ .shift = true };
    }

    /// Convinence function for generating a control modifier
    pub fn control() KeyModifier {
        return KeyModifier{ .control = true };
    }

    /// Convinence function for generating a alt modifier
    pub fn alt() KeyModifier {
        return KeyModifier{ .alt = true };
    }

    /// Convinence function for generating a super modifier
    pub fn super() KeyModifier {
        return KeyModifier{ .super = true };
    }

    /// Convinence function for generating a hyper modifier
    pub fn hyper() KeyModifier {
        return KeyModifier{ .hyper = true };
    }

    /// Convinence function for generating a meta modifier
    pub fn meta() KeyModifier {
        return KeyModifier{ .meta = true };
    }

    /// Convinence function for generating a Caps Lock modifier
    pub fn caps_lock() KeyModifier {
        return KeyModifier{ .caps_lock = true };
    }

    /// Convinence function for generating a Num Lock modifier
    pub fn num_lock() KeyModifier {
        return KeyModifier{ .num_lock = true };
    }

    pub fn format(value: KeyModifier, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        if (value.shift) try writer.print("Shift ", .{});
        if (value.alt) try writer.print("Alt ", .{});
        if (value.control) try writer.print("Ctrl ", .{});
        if (value.hyper) try writer.print("Hyper ", .{});
        if (value.super) try writer.print("Super ", .{});
        if (value.meta) try writer.print("Meta ", .{});
        if (value.caps_lock) try writer.print("CapsLock ", .{});
        if (value.num_lock) try writer.print("NumLock", .{});
    }
};

/// Key events are reported from keypress data sent to the terminal
pub const KeyEvent = struct {
    /// The Key code actuated
    code: KeyCode,
    /// The Modifier fields for the key
    modifier: KeyModifier,
    /// Actions are only reported if the `report_event_types` progressive
    /// enhancements have been requested, otherwise ".press" is always reported
    action: ?KeyAction = null,
    /// Alternate Keycodes. This Data is only notable if the `report_alternate_keys`
    /// enhancement has been requested
    alternate: AlternateKeyCodes = AlternateKeyCodes{},

    pub fn format(value: KeyEvent, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        try writer.print("Code: {?}\n", .{value.code});
        try writer.print("\tModifiers: {?}\n", .{value.modifier});
        if (value.action) |action| try writer.print("\tAction: {?}\n", .{action}) else try writer.print("\tAction: press\n", .{});
        try writer.print("\tAlternates: {?}\n", .{value.alternate});
    }
};

/// Data around alternate key codes. Data is null unless the `report_alternate_keys`
/// is requested
pub const AlternateKeyCodes = struct {
    /// The Shifted version of they key.
    shifted_key: ?KeyCode = null,
    /// The Base layout key
    base_layout_key: ?KeyCode = null,

    pub fn format(value: AlternateKeyCodes, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        if (value.shifted_key) |shifted| try writer.print("shifted: {?}", .{shifted});
        if (value.base_layout_key) |base| try writer.print("base layout: {?}", .{base});
    }
};

pub const KeyCodeTags = enum {
    Backspace,
    Enter,
    Left,
    Right,
    Up,
    Down,
    Home,
    End,
    PageUp,
    PageDown,
    Tab,
    BackTab,
    Delete,
    Insert,
    F,
    Char,
    KpKey,
    Null,
    Esc,
    CapsLock,
    ScrollLock,
    NumLock,
    PrintScreen,
    Pause,
    Menu,
    KeypadBegin,
    Media,
    Modifier,
};

/// Keycodes for KeyEvents
pub const KeyCode = union(KeyCodeTags) {
    /// Backspace key
    Backspace,
    /// Enter key
    Enter,
    /// Left arrow key
    Left,
    /// Right arrow key
    Right,
    /// Up arrow key
    Up,
    /// Down arrow key
    Down,
    /// Home key
    Home,
    /// End key
    End,
    /// Page up key
    PageUp,
    /// Page down key
    PageDown,
    /// Tab key
    Tab,
    /// Shift + Tab key
    BackTab,
    /// Delete key
    Delete,
    /// Insert key
    Insert,
    /// F key
    ///
    /// `F(1)` represents F1 key, etc
    F: u8,
    /// A character
    ///
    /// `Char('c')` represents `c` unicode character, etc
    Char: u21,
    /// Key Pad Keys
    ///
    /// **Note:** this will only be read if Progressive Enhancement is set
    KpKey: u8,
    /// Null
    Null,
    /// Escape key
    Esc,
    /// Caps Lock key
    ///
    /// **Note:** this key can only be read if `disambiguate_escape_codes`
    /// progressive enhancement has been enabled
    CapsLock,
    /// Scroll Lock key
    ///
    /// **Note:** this key can only be read if `disambiguate_escape_codes`
    /// progressive enhancement has been enabled
    ScrollLock,
    /// Num Lock key
    ///
    /// **Note:** this key can only be read if `disambiguate_escape_codes`
    /// progressive enhancement has been enabled
    NumLock,
    /// Print Screen key
    ///
    /// **Note:** this key can only be read if `disambiguate_escape_codes`
    /// progressive enhancement has been enabled
    PrintScreen,
    /// Pause key
    ///
    /// **Note:** this key can only be read if `disambiguate_escape_codes`
    /// progressive enhancement has been enabled
    Pause,
    /// Menu key
    ///
    /// **Note:** this key can only be read if `disambiguate_escape_codes`
    /// progressive enhancement has been enabled
    Menu,
    /// The "Begin" key (often mapped to the 5 key when Num Lock is turned on)
    ///
    /// **Note:** this key can only be read if `disambiguate_escape_codes`
    /// progressive enhancement has been enabled
    KeypadBegin,
    /// A media key
    ///
    /// **Note:** this key can only be read if `disambiguate_escape_codes`
    /// progressive enhancement has been enabled
    Media: MediaKeyCode,
    /// A modifier key
    ///
    /// **Note:** this key can only be read if the `disambiguate_escape_codes`
    /// and `report_all_keys_as_escape_codes` progressive enhancements have been
    /// enabled
    Modifier: ModifierKeyCode,

    pub fn format(value: KeyCode, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;

        switch (value) {
            .Char => |c| {
                try writer.print("'{u}'", .{c});
            },
            .F => |f| {
                try writer.print("F{d}", .{f});
            },
            .KpKey => |k| {
                try writer.print("{d}", .{k});
            },
            .Modifier => |m| {
                try std.fmt.format(writer, "{s}", .{@tagName(m)});
            },
            .Media => |m| {
                try std.fmt.format(writer, "{s}", .{@tagName(m)});
            },
            inline else => |v| {
                _ = v;
                try std.fmt.format(writer, "{s}", .{@tagName(value)});
            },
        }
    }
};

pub const MediaKeyCode = enum {
    /// Play media key
    Play,
    /// Pause media key
    Pause,
    /// Play/Pause media key
    PlayPause,
    /// Reverse media key
    Reverse,
    /// Stop media key
    Stop,
    /// Fast-forward media key
    FastForward,
    /// Rewind media key
    Rewind,
    /// Next-track media key
    TrackNext,
    /// Previous-track media key
    TrackPrevious,
    /// Record media key
    Record,
    /// Lower-volume media key
    LowerVolume,
    /// Raise-volume media key
    RaiseVolume,
    /// Mute media key
    MuteVolume,
};

pub const ModifierKeyCode = enum {
    /// Left Shift key
    LeftShift,
    /// Left Control key
    LeftControl,
    /// Left Alt key
    LeftAlt,
    /// Left Super key
    LeftSuper,
    /// Left Hyper key
    LeftHyper,
    /// Left Meta key
    LeftMeta,
    /// Right Shift key
    RightShift,
    /// Right Control key
    RightControl,
    /// Right Alt key
    RightAlt,
    /// Right Super key
    RightSuper,
    /// Right Hyper key
    RightHyper,
    /// Right Meta key
    RightMeta,
    /// Iso Level3 Shift key
    IsoLevel3Shift,
    /// Iso Level5 Shift key
    IsoLevel5Shift,
};
