const std = @import("std");
const Allocator = std.mem.Allocator;

/// A bitmask for all key modifiers. This is taken directly from the
/// GLFW representation, but we use this generically.
///
/// IMPORTANT: Any changes here update include/ghostty.h
pub const Mods = packed struct(u8) {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,
    _padding: u2 = 0,

    /// Returns true if no modifiers are set.
    pub fn empty(self: Mods) bool {
        return @as(u8, @bitCast(self)) == 0;
    }

    /// Returns true if two mods are equal.
    pub fn equal(self: Mods, other: Mods) bool {
        return @as(u8, @bitCast(self)) == @as(u8, @bitCast(other));
    }

    /// Return mods that are only relevant for bindings.
    pub fn binding(self: Mods) Mods {
        return .{
            .shift = self.shift,
            .ctrl = self.ctrl,
            .alt = self.alt,
            .super = self.super,
        };
    }

    /// Returns the mods without locks set.
    pub fn withoutLocks(self: Mods) Mods {
        var copy = self;
        copy.caps_lock = false;
        copy.num_lock = false;
        return copy;
    }

    // For our own understanding
    test {
        const testing = std.testing;
        try testing.expectEqual(@as(u8, @bitCast(Mods{})), @as(u8, 0b0));
        try testing.expectEqual(
            @as(u8, @bitCast(Mods{ .shift = true })),
            @as(u8, 0b0000_0001),
        );
    }
};

/// The action associated with an input event. This is backed by a c_int
/// so that we can use the enum as-is for our embedding API.
///
/// IMPORTANT: Any changes here update include/ghostty.h
pub const Action = enum(c_int) {
    release,
    press,
    repeat,
};

/// The set of keys that can map to keybindings. These have no fixed enum
/// values because we map platform-specific keys to this set. Note that
/// this only needs to accommodate what maps to a key. If a key is not bound
/// to anything and the key can be mapped to a printable character, then that
/// unicode character is sent directly to the pty.
///
/// This is backed by a c_int so we can use this as-is for our embedding API.
///
/// IMPORTANT: Any changes here update include/ghostty.h
pub const Key = enum(c_int) {
    invalid,

    // a-z
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,

    // numbers
    zero,
    one,
    two,
    three,
    four,
    five,
    six,
    seven,
    eight,
    nine,

    // puncuation
    semicolon,
    space,
    apostrophe,
    comma,
    grave_accent, // `
    period,
    slash,
    minus,
    equal,
    left_bracket, // [
    right_bracket, // ]
    backslash, // /

    // control
    up,
    down,
    right,
    left,
    home,
    end,
    insert,
    delete,
    caps_lock,
    scroll_lock,
    num_lock,
    page_up,
    page_down,
    escape,
    enter,
    tab,
    backspace,
    print_screen,
    pause,

    // function keys
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    f13,
    f14,
    f15,
    f16,
    f17,
    f18,
    f19,
    f20,
    f21,
    f22,
    f23,
    f24,
    f25,

    // keypad
    kp_0,
    kp_1,
    kp_2,
    kp_3,
    kp_4,
    kp_5,
    kp_6,
    kp_7,
    kp_8,
    kp_9,
    kp_decimal,
    kp_divide,
    kp_multiply,
    kp_subtract,
    kp_add,
    kp_enter,
    kp_equal,

    // modifiers
    left_shift,
    left_control,
    left_alt,
    left_super,
    right_shift,
    right_control,
    right_alt,
    right_super,

    // To support more keys (there are obviously more!) add them here
    // and ensure the mapping is up to date in the Window key handler.

    /// Converts an ASCII character to a key, if possible. This returns
    /// null if the character is unknown.
    ///
    /// Note that this can't distinguish between physical keys, i.e. '0'
    /// may be from the number row or the keypad, but it always maps
    /// to '.zero'.
    ///
    /// This is what we want, we awnt people to create keybindings that
    /// are independent of the physical key.
    pub fn fromASCII(ch: u8) ?Key {
        return switch (ch) {
            'a' => .a,
            'b' => .b,
            'c' => .c,
            'd' => .d,
            'e' => .e,
            'f' => .f,
            'g' => .g,
            'h' => .h,
            'i' => .i,
            'j' => .j,
            'k' => .k,
            'l' => .l,
            'm' => .m,
            'n' => .n,
            'o' => .o,
            'p' => .p,
            'q' => .q,
            'r' => .r,
            's' => .s,
            't' => .t,
            'u' => .u,
            'v' => .v,
            'w' => .w,
            'x' => .x,
            'y' => .y,
            'z' => .z,
            '0' => .zero,
            '1' => .one,
            '2' => .two,
            '3' => .three,
            '4' => .four,
            '5' => .five,
            '6' => .six,
            '7' => .seven,
            '8' => .eight,
            '9' => .nine,
            ';' => .semicolon,
            ' ' => .space,
            '\'' => .apostrophe,
            ',' => .comma,
            '`' => .grave_accent,
            '.' => .period,
            '/' => .slash,
            '-' => .minus,
            '=' => .equal,
            '[' => .left_bracket,
            ']' => .right_bracket,
            '\\' => .backslash,
            else => null,
        };
    }

    /// True if this key represents a printable character.
    pub fn printable(self: Key) bool {
        return switch (self) {
            .a,
            .b,
            .c,
            .d,
            .e,
            .f,
            .g,
            .h,
            .i,
            .j,
            .k,
            .l,
            .m,
            .n,
            .o,
            .p,
            .q,
            .r,
            .s,
            .t,
            .u,
            .v,
            .w,
            .x,
            .y,
            .z,
            .zero,
            .one,
            .two,
            .three,
            .four,
            .five,
            .six,
            .seven,
            .eight,
            .nine,
            .semicolon,
            .space,
            .apostrophe,
            .comma,
            .grave_accent,
            .period,
            .slash,
            .minus,
            .equal,
            .left_bracket,
            .right_bracket,
            .backslash,
            .kp_0,
            .kp_1,
            .kp_2,
            .kp_3,
            .kp_4,
            .kp_5,
            .kp_6,
            .kp_7,
            .kp_8,
            .kp_9,
            .kp_decimal,
            .kp_divide,
            .kp_multiply,
            .kp_subtract,
            .kp_add,
            .kp_equal,
            => true,

            else => false,
        };
    }
};
