//! This is the list of "PC style function keys" that xterm supports for
//! the legacy keyboard protocols. These always take priority since at the
//! time of writing this, even the most modern keyboard protocols still
//! are backwards compatible with regards to these sequences.
//!
//! This is based on a variety of sources cross-referenced but mostly
//! based on foot's keymap.h: https://codeberg.org/dnkl/foot/src/branch/master/keymap.h

const std = @import("std");
const key = @import("key.zig");

pub const CursorMode = enum { any, normal, application };
pub const KeypadMode = enum { any, normal, application };

/// A bit confusing so I'll document this one: this is the "modify other keys"
/// setting. We only change behavior for "set_other" which is ESC [ 4; 2 m.
/// So this can be "any" which means we don't care what's going on. Or it
/// can be "set" which means modify keys must be set EXCEPT FOR "other keys"
/// mode, and "set_other" which means modify keys must be set to "other keys"
/// mode.
///
/// See: https://invisible-island.net/xterm/modified-keys.html
pub const ModifyKeys = enum {
    any,
    set,
    set_other,
};

/// A single entry in the table of keys.
pub const Entry = struct {
    /// The exact set of modifiers that must be active for this entry to match.
    /// If mods_empty_is_any is true then empty mods means any set of mods can
    /// match. Otherwise, empty mods means no mods must be active.
    mods: key.Mods = .{},
    mods_empty_is_any: bool = true,

    /// The state required for cursor/keypad mode.
    cursor: CursorMode = .any,
    keypad: KeypadMode = .any,

    /// Whether or not this entry should be used
    modify_other_keys: ModifyKeys = .any,

    /// The sequence to send to the pty if this entry matches.
    sequence: []const u8,
};

/// The list of modifier combinations for modify other key sequences.
/// The mode value is index + 2.
pub const modifiers: []const key.Mods = &.{
    .{ .shift = true },
    .{ .alt = true },
    .{ .shift = true, .alt = true },
    .{ .ctrl = true },
    .{ .shift = true, .ctrl = true },
    .{ .alt = true, .ctrl = true },
    .{ .shift = true, .alt = true, .ctrl = true },
    .{ .super = true },
    .{ .shift = true, .super = true },
    .{ .alt = true, .super = true },
    .{ .shift = true, .alt = true, .super = true },
    .{ .ctrl = true, .super = true },
    .{ .shift = true, .ctrl = true, .super = true },
    .{ .alt = true, .ctrl = true, .super = true },
    .{ .shift = true, .alt = true, .ctrl = true, .super = true },
};

/// This is the array of entries for the PC style function keys as mapped to
/// our set of possible key codes. Not every key has any entries.
pub const KeyEntryArray = std.EnumArray(key.Key, []const Entry);

// The list of keys that we support and their entry values. It is expected
// that you'll just use a for loop through the entry values, there are never
// more than a couple dozen or so.
pub const keys = keys: {
    var result = KeyEntryArray.initFill(&.{});

    result.set(.up, pcStyle("\x1b[1;{}A") ++ cursorKey("\x1b[A", "\x1bOA"));
    result.set(.down, pcStyle("\x1b[1;{}B") ++ cursorKey("\x1b[B", "\x1bOB"));
    result.set(.right, pcStyle("\x1b[1;{}C") ++ cursorKey("\x1b[C", "\x1bOC"));
    result.set(.left, pcStyle("\x1b[1;{}D") ++ cursorKey("\x1b[D", "\x1bOD"));
    result.set(.home, pcStyle("\x1b[1;{}H") ++ cursorKey("\x1b[H", "\x1bOH"));
    result.set(.end, pcStyle("\x1b[1;{}F") ++ cursorKey("\x1b[F", "\x1bOF"));
    result.set(.insert, pcStyle("\x1b[2;{}~") ++ .{.{ .sequence = "\x1B[2~" }});
    result.set(.delete, pcStyle("\x1b[3;{}~") ++ .{.{ .sequence = "\x1B[3~" }});
    result.set(.page_up, pcStyle("\x1b[5;{}~") ++ .{.{ .sequence = "\x1B[5~" }});
    result.set(.page_down, pcStyle("\x1b[6;{}~") ++ .{.{ .sequence = "\x1B[6~" }});

    // Function Keys. todo: f13-f35 but we need to add to input.Key
    result.set(.f1, pcStyle("\x1b[1;{}P") ++ .{.{ .sequence = "\x1BOP" }});
    result.set(.f2, pcStyle("\x1b[1;{}Q") ++ .{.{ .sequence = "\x1BOQ" }});
    result.set(.f3, pcStyle("\x1b[1;{}R") ++ .{.{ .sequence = "\x1BOR" }});
    result.set(.f4, pcStyle("\x1b[1;{}S") ++ .{.{ .sequence = "\x1BOS" }});
    result.set(.f5, pcStyle("\x1b[15;{}~") ++ .{.{ .sequence = "\x1B[15~" }});
    result.set(.f6, pcStyle("\x1b[17;{}~") ++ .{.{ .sequence = "\x1B[17~" }});
    result.set(.f7, pcStyle("\x1b[18;{}~") ++ .{.{ .sequence = "\x1B[18~" }});
    result.set(.f8, pcStyle("\x1b[19;{}~") ++ .{.{ .sequence = "\x1B[19~" }});
    result.set(.f9, pcStyle("\x1b[20;{}~") ++ .{.{ .sequence = "\x1B[20~" }});
    result.set(.f10, pcStyle("\x1b[21;{}~") ++ .{.{ .sequence = "\x1B[21~" }});
    result.set(.f11, pcStyle("\x1b[23;{}~") ++ .{.{ .sequence = "\x1B[23~" }});
    result.set(.f12, pcStyle("\x1b[24;{}~") ++ .{.{ .sequence = "\x1B[24~" }});

    // Keypad keys
    result.set(.kp_0, kpDefault("p") ++ pcStyle("\x1bO{}p"));
    result.set(.kp_1, kpDefault("q") ++ pcStyle("\x1bO{}q"));
    result.set(.kp_2, kpDefault("r") ++ pcStyle("\x1bO{}r"));
    result.set(.kp_3, kpDefault("s") ++ pcStyle("\x1bO{}s"));
    result.set(.kp_4, kpDefault("t") ++ pcStyle("\x1bO{}t"));
    result.set(.kp_5, kpDefault("u") ++ pcStyle("\x1bO{}u"));
    result.set(.kp_6, kpDefault("v") ++ pcStyle("\x1bO{}v"));
    result.set(.kp_7, kpDefault("w") ++ pcStyle("\x1bO{}w"));
    result.set(.kp_8, kpDefault("x") ++ pcStyle("\x1bO{}x"));
    result.set(.kp_9, kpDefault("y") ++ pcStyle("\x1bO{}y"));
    result.set(.kp_decimal, kpDefault("n") ++ pcStyle("\x1bO{}n"));
    result.set(.kp_divide, kpDefault("o") ++ pcStyle("\x1bO{}o"));
    result.set(.kp_multiply, kpDefault("j") ++ pcStyle("\x1bO{}j"));
    result.set(.kp_subtract, kpDefault("m") ++ pcStyle("\x1bO{}m"));
    result.set(.kp_add, kpDefault("k") ++ pcStyle("\x1bO{}k"));
    result.set(.kp_enter, kpDefault("M") ++ pcStyle("\x1bO{}M") ++ .{.{ .sequence = "\r" }});
    result.set(.kp_up, pcStyle("\x1b[1;{}A") ++ cursorKey("\x1b[A", "\x1bOA"));
    result.set(.kp_down, pcStyle("\x1b[1;{}B") ++ cursorKey("\x1b[B", "\x1bOB"));
    result.set(.kp_right, pcStyle("\x1b[1;{}C") ++ cursorKey("\x1b[C", "\x1bOC"));
    result.set(.kp_left, pcStyle("\x1b[1;{}D") ++ cursorKey("\x1b[D", "\x1bOD"));
    result.set(.kp_home, pcStyle("\x1b[1;{}H") ++ cursorKey("\x1b[H", "\x1bOH"));
    result.set(.kp_end, pcStyle("\x1b[1;{}F") ++ cursorKey("\x1b[F", "\x1bOF"));
    result.set(.kp_insert, pcStyle("\x1b[2;{}~") ++ .{.{ .sequence = "\x1B[2~" }});
    result.set(.kp_delete, pcStyle("\x1b[3;{}~") ++ .{.{ .sequence = "\x1B[3~" }});
    result.set(.kp_page_up, pcStyle("\x1b[5;{}~") ++ .{.{ .sequence = "\x1B[5~" }});
    result.set(.kp_page_down, pcStyle("\x1b[6;{}~") ++ .{.{ .sequence = "\x1B[6~" }});

    result.set(.backspace, &.{
        // Modify Keys Normal
        .{ .mods = .{ .shift = true }, .modify_other_keys = .set, .sequence = "\x7f" },
        .{ .mods = .{ .alt = true }, .modify_other_keys = .set, .sequence = "\x1b\x7f" },
        .{ .mods = .{ .alt = true, .shift = true }, .modify_other_keys = .set, .sequence = "\x1b\x7f" },
        .{ .mods = .{ .ctrl = true, .shift = true }, .modify_other_keys = .set, .sequence = "\x08" },
        .{ .mods = .{ .alt = true, .ctrl = true }, .modify_other_keys = .set, .sequence = "\x1b\x08" },
        .{ .mods = .{ .super = true }, .modify_other_keys = .set, .sequence = "\x7f" },
        .{ .mods = .{ .super = true, .shift = true }, .modify_other_keys = .set, .sequence = "\x7f" },
        .{ .mods = .{ .alt = true, .super = true }, .modify_other_keys = .set, .sequence = "\x1b\x7f" },
        .{ .mods = .{ .alt = true, .super = true, .shift = true }, .modify_other_keys = .set, .sequence = "\x1b\x7f" },
        .{ .mods = .{ .super = true, .ctrl = true }, .modify_other_keys = .set, .sequence = "\x08" },
        .{ .mods = .{ .super = true, .ctrl = true, .shift = true }, .modify_other_keys = .set, .sequence = "\x08" },
        .{ .mods = .{ .alt = true, .super = true, .ctrl = true }, .modify_other_keys = .set, .sequence = "\x1b\x08" },
        .{ .mods = .{ .alt = true, .super = true, .ctrl = true, .shift = true }, .modify_other_keys = .set, .sequence = "\x1b\x08" },

        // Modify Keys Other
        .{ .mods = .{ .shift = true }, .modify_other_keys = .set_other, .sequence = "\x1b[27;2;127~" },
        .{ .mods = .{ .alt = true }, .modify_other_keys = .set_other, .sequence = "\x1b[27;3;127~" },
        .{ .mods = .{ .alt = true, .shift = true }, .modify_other_keys = .set_other, .sequence = "\x1b[27;4;127~" },
        .{ .mods = .{ .ctrl = true, .shift = true }, .modify_other_keys = .set_other, .sequence = "\x1b[27;6;127~" },
        .{ .mods = .{ .alt = true, .ctrl = true }, .modify_other_keys = .set_other, .sequence = "\x1b[27;7;127~" },
        .{ .mods = .{ .alt = true, .shift = true, .ctrl = true }, .modify_other_keys = .set_other, .sequence = "\x1b[27;8;127~" },
        .{ .mods = .{ .super = true }, .modify_other_keys = .set_other, .sequence = "\x1b[27;9;127~" },
        .{ .mods = .{ .super = true, .shift = true }, .modify_other_keys = .set_other, .sequence = "\x1b[27;10;127~" },
        .{ .mods = .{ .alt = true, .super = true }, .modify_other_keys = .set_other, .sequence = "\x1b[27;11;127~" },
        .{ .mods = .{ .alt = true, .super = true, .shift = true }, .modify_other_keys = .set_other, .sequence = "\x1b[27;12;127~" },
        .{ .mods = .{ .super = true, .ctrl = true }, .modify_other_keys = .set_other, .sequence = "\x1b[27;13;127~" },
        .{ .mods = .{ .super = true, .ctrl = true, .shift = true }, .modify_other_keys = .set_other, .sequence = "\x1b[27;14;127~" },
        .{ .mods = .{ .alt = true, .super = true, .ctrl = true }, .modify_other_keys = .set_other, .sequence = "\x1b[27;15;127~" },
        .{ .mods = .{ .alt = true, .super = true, .ctrl = true, .shift = true }, .modify_other_keys = .set_other, .sequence = "\x1b[27;16;127~" },

        .{ .mods = .{ .ctrl = true }, .sequence = "\x08" },
        .{ .sequence = "\x7f" },
    });

    result.set(.tab, &.{
        // Modify Keys Normal
        .{ .mods = .{ .shift = true }, .modify_other_keys = .set, .sequence = "\x1b[Z" },
        .{ .mods = .{ .alt = true }, .modify_other_keys = .set, .sequence = "\x1b\t" },

        // Modify Keys Other
        .{ .mods = .{ .shift = true }, .modify_other_keys = .set_other, .sequence = "\x1b[27;2;9~" },
        .{ .mods = .{ .alt = true }, .modify_other_keys = .set_other, .sequence = "\x1b[27;3;9~" },

        // Everything else
        .{ .mods = .{ .alt = true, .shift = true }, .sequence = "\x1b[27;4;9~" },
        .{ .mods = .{ .ctrl = true }, .sequence = "\x1b[27;5;9~" },
        .{ .mods = .{ .ctrl = true, .shift = true }, .sequence = "\x1b[27;6;9~" },
        .{ .mods = .{ .alt = true, .ctrl = true }, .sequence = "\x1b[27;7;9~" },
        .{ .mods = .{ .alt = true, .ctrl = true, .shift = true }, .sequence = "\x1b[27;8;9~" },
        .{ .mods = .{ .super = true }, .sequence = "\x1b[27;9;9~" },
        .{ .mods = .{ .super = true, .shift = true }, .sequence = "\x1b[27;10;9~" },
        .{ .mods = .{ .alt = true, .super = true }, .sequence = "\x1b[27;11;9~" },
        .{ .mods = .{ .alt = true, .super = true, .shift = true }, .sequence = "\x1b[27;12;9~" },
        .{ .mods = .{ .super = true, .ctrl = true }, .sequence = "\x1b[27;13;9~" },
        .{ .mods = .{ .super = true, .ctrl = true, .shift = true }, .sequence = "\x1b[27;14;9~" },
        .{ .mods = .{ .alt = true, .super = true, .ctrl = true }, .sequence = "\x1b[27;15;9~" },
        .{ .mods = .{ .alt = true, .super = true, .ctrl = true, .shift = true }, .sequence = "\x1b[27;16;9~" },

        .{ .sequence = "\t" },
    });

    result.set(.enter, &.{
        .{ .mods = .{ .shift = true }, .sequence = "\x1b[27;2;13~" },

        // Modify Keys Normal
        .{ .mods = .{ .alt = true }, .modify_other_keys = .set, .sequence = "\x1b\r" },

        // Modify Keys Other
        .{ .mods = .{ .alt = true }, .modify_other_keys = .set_other, .sequence = "\x1b[27;3;13~" },

        // Everything else
        .{ .mods = .{ .alt = true, .shift = true }, .sequence = "\x1b[27;4;13~" },
        .{ .mods = .{ .ctrl = true }, .sequence = "\x1b[27;5;13~" },
        .{ .mods = .{ .ctrl = true, .shift = true }, .sequence = "\x1b[27;6;13~" },
        .{ .mods = .{ .alt = true, .ctrl = true }, .sequence = "\x1b[27;7;13~" },
        .{ .mods = .{ .alt = true, .ctrl = true, .shift = true }, .sequence = "\x1b[27;8;13~" },
        .{ .mods = .{ .super = true }, .sequence = "\x1b[27;9;13~" },
        .{ .mods = .{ .super = true, .shift = true }, .sequence = "\x1b[27;10;13~" },
        .{ .mods = .{ .alt = true, .super = true }, .sequence = "\x1b[27;11;13~" },
        .{ .mods = .{ .alt = true, .super = true, .shift = true }, .sequence = "\x1b[27;12;13~" },
        .{ .mods = .{ .super = true, .ctrl = true }, .sequence = "\x1b[27;13;13~" },
        .{ .mods = .{ .super = true, .ctrl = true, .shift = true }, .sequence = "\x1b[27;14;13~" },
        .{ .mods = .{ .alt = true, .super = true, .ctrl = true }, .sequence = "\x1b[27;15;13~" },
        .{ .mods = .{ .alt = true, .super = true, .ctrl = true, .shift = true }, .sequence = "\x1b[27;16;13~" },

        .{ .sequence = "\r" },
    });

    result.set(.escape, &.{
        .{ .mods = .{ .shift = true }, .sequence = "\x1b[27;2;27~" },
        .{ .mods = .{ .alt = true }, .sequence = "\x1b\x1b" },
        .{ .mods = .{ .alt = true, .shift = true }, .sequence = "\x1b[27;4;27~" },
        .{ .mods = .{ .ctrl = true }, .sequence = "\x1b[27;5;27~" },
        .{ .mods = .{ .ctrl = true, .shift = true }, .sequence = "\x1b[27;6;27~" },
        .{ .mods = .{ .alt = true, .ctrl = true }, .sequence = "\x1b[27;7;27~" },
        .{ .mods = .{ .alt = true, .ctrl = true, .shift = true }, .sequence = "\x1b[27;8;27~" },
        .{ .mods = .{ .super = true }, .sequence = "\x1b[27;9;27~" },
        .{ .mods = .{ .super = true, .shift = true }, .sequence = "\x1b[27;10;27~" },
        .{ .mods = .{ .alt = true, .super = true }, .sequence = "\x1b[27;11;27~" },
        .{ .mods = .{ .alt = true, .super = true, .shift = true }, .sequence = "\x1b[27;12;27~" },
        .{ .mods = .{ .super = true, .ctrl = true }, .sequence = "\x1b[27;13;27~" },
        .{ .mods = .{ .super = true, .ctrl = true, .shift = true }, .sequence = "\x1b[27;14;27~" },
        .{ .mods = .{ .alt = true, .super = true, .ctrl = true }, .sequence = "\x1b[27;15;27~" },
        .{ .mods = .{ .alt = true, .super = true, .ctrl = true, .shift = true }, .sequence = "\x1b[27;16;27~" },
        .{ .sequence = "\x1b" },
    });

    break :keys result;
};

/// Returns the default keypad application mode entry.
fn kpDefault(comptime suffix: []const u8) []const Entry {
    return &.{
        .{
            .mods_empty_is_any = false,
            .keypad = .application,
            .sequence = "\x1bO" ++ suffix,
        },
    };
}

/// Returns entries that are dependent on cursor key settings.
fn cursorKey(
    comptime normal: []const u8,
    comptime application: []const u8,
) []const Entry {
    return &.{
        .{ .cursor = .normal, .sequence = normal },
        .{ .cursor = .application, .sequence = application },
    };
}

/// Constructs a set of pcStyle function keys using the given format. The
/// format should have exactly one "hole" for the mods code.
/// Example: "\x1b[11;{}~" for F1.
fn pcStyle(comptime fmt: []const u8) []const Entry {
    // The comptime {} wrapper is superflous but it prevents us from
    // accidentally running this function at runtime.
    comptime {
        var entries: [modifiers.len]Entry = undefined;
        for (modifiers, 2.., 0..) |mods, code, i| {
            entries[i] = .{
                .mods = mods,
                .sequence = std.fmt.comptimePrint(fmt, .{code}),
            };
        }

        return &entries;
    }
}

test "keys" {
    const testing = std.testing;

    // Force resolution for comptime evaluation.
    _ = keys;

    // All key sequences must fit into a termio array.
    const max = @import("../termio.zig").Message.WriteReq.Small.Max;
    for (keys.values) |entries| {
        for (entries) |entry| {
            try testing.expect(entry.sequence.len <= max);
        }
    }
}
