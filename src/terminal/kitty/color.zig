const std = @import("std");
const terminal = @import("../main.zig");
const RGB = terminal.color.RGB;
const Terminator = terminal.osc.Terminator;

pub const OSC = struct {
    pub const Request = union(enum) {
        query: Kind,
        set: struct { key: Kind, color: RGB },
        reset: Kind,
    };

    /// list of requests
    list: std.ArrayList(Request),

    /// We must reply with the same string terminator (ST) as used in the
    /// request.
    terminator: Terminator = .st,
};

pub const Special = enum {
    foreground,
    background,
    selection_foreground,
    selection_background,
    cursor,
    cursor_text,
    visual_bell,
    second_transparent_background,
};

pub const Kind = union(enum) {
    pub const max: usize = std.math.maxInt(u8) + @typeInfo(Special).Enum.fields.len;

    palette: u8,
    special: Special,

    pub fn parse(key: []const u8) ?Kind {
        return kind: {
            const s = std.meta.stringToEnum(Special, key) orelse {
                const p = std.fmt.parseUnsigned(u8, key, 10) catch {
                    break :kind null;
                };
                break :kind Kind{ .palette = p };
            };
            break :kind Kind{ .special = s };
        };
    }

    pub fn format(
        self: Kind,
        comptime layout: []const u8,
        opts: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = layout;
        _ = opts;

        // Format as a number if its a palette color otherwise
        // format as a string.
        if (self == .palette) {
            try writer.print("{d}", .{self.palette});
        } else {
            try writer.print("{s}", .{@tagName(self.special)});
        }
    }
};

test "OSC: kitty color protocol kind string" {
    const testing = std.testing;

    var buf: [256]u8 = undefined;
    {
        const actual = try std.fmt.bufPrint(&buf, "{}", .{Kind{ .special = .foreground }});
        try testing.expectEqualStrings("foreground", actual);
    }
    {
        const actual = try std.fmt.bufPrint(&buf, "{}", .{Kind{ .palette = 42 }});
        try testing.expectEqualStrings("42", actual);
    }
}
