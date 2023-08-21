//! Kitty graphics protocol support.
//!
//! Documentation:
//! https://sw.kovidgoyal.net/kitty/graphics-protocol

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

/// The key-value pairs for the control information for a command. The
/// keys are always single characters and the values are either single
/// characters or 32-bit unsigned integers.
///
/// For the value of this: if the value is a single printable ASCII character
/// it is the ASCII code. Otherwise, it is parsed as a 32-bit unsigned integer.
const KV = std.AutoHashMapUnmanaged(u8, u32);

/// Command parser parses the Kitty graphics protocol escape sequence.
pub const CommandParser = struct {
    /// The memory used by the parser is stored in an arena because it is
    /// all freed at the end of the command.
    arena: ArenaAllocator,

    /// This is the list of KV pairs that we're building up.
    kv: KV = .{},

    /// This is used as a buffer to store the key/value of a KV pair.
    /// The value of a KV pair is at most a 32-bit integer which at most
    /// is 10 characters (4294967295).
    kv_temp: [10]u8 = undefined,
    kv_temp_len: u4 = 0,

    /// Current kv key
    kv_current: u8 = 0,

    /// This is the list of bytes that contains both KV data and final
    /// data. You shouldn't access this directly.
    data: std.ArrayListUnmanaged(u8) = .{},

    /// Internal state for parsing.
    data_i: usize = 0,
    state: State = .control_key,

    const State = enum {
        /// Parsing k/v pairs. The "ignore" variants are in that state
        /// but ignore any data because we know they're invalid.
        control_key,
        control_key_ignore,
        control_value,
        control_value_ignore,

        /// We're parsing the data blob.
        data,
    };

    /// Initialize the parser. The allocator given will be used only for
    /// temporary state and nothing long-lived.
    pub fn init(alloc: Allocator) CommandParser {
        var arena = ArenaAllocator.init(alloc);
        errdefer arena.deinit();
        return .{
            .arena = arena,
        };
    }

    pub fn deinit(self: *CommandParser) void {
        // We don't free the hash map or array list because its in the arena
        self.arena.deinit();
    }

    /// Feed a single byte to the parser.
    ///
    /// The first byte to start parsing should be the byte immediately following
    /// the "G" in the APC sequence, i.e. "\x1b_G123" the first byte should
    /// be "1".
    pub fn feed(self: *CommandParser, c: u8) !void {
        switch (self.state) {
            .control_key => switch (c) {
                // '=' means the key is complete and we're moving to the value.
                '=' => if (self.kv_temp_len != 1) {
                    // All control keys are a single character right now so
                    // if we're not a single character just ignore follow-up
                    // data.
                    self.state = .control_value_ignore;
                    self.kv_temp_len = 0;
                } else {
                    self.kv_current = self.kv_temp[0];
                    self.kv_temp_len = 0;
                    self.state = .control_value;
                },

                else => try self.accumulateValue(c, .control_key_ignore),
            },

            .control_key_ignore => switch (c) {
                '=' => self.state = .control_value_ignore,
                else => {},
            },

            .control_value => switch (c) {
                ',' => try self.finishValue(.control_key), // move to next key
                ';' => try self.finishValue(.data), // move to data
                else => try self.accumulateValue(c, .control_value_ignore),
            },

            .control_value_ignore => switch (c) {
                ',' => self.state = .control_key_ignore,
                ';' => self.state = .data,
                else => {},
            },

            .data => try self.data.append(self.arena.allocator(), c),
        }

        // We always add to our data list because this is our stable
        // array of bytes that we'll reference everywhere else.
    }

    /// Complete the parsing. This must be called after all the
    /// bytes have been fed to the parser.
    ///
    /// The allocator given will be used for the long-lived data
    /// of the final command.
    pub fn complete(self: *CommandParser, alloc: Allocator) !Command {
        switch (self.state) {
            // We can't ever end in the control key state and be valid.
            // This means the command looked something like "a=1,b"
            .control_key, .control_key_ignore => return error.InvalidFormat,

            // Some commands (i.e. placements) end without extra data so
            // we end in the value state. i.e. "a=1,b=2"
            .control_value => try self.finishValue(.data),
            .control_value_ignore => {},

            // Most commands end in data, i.e. "a=1,b=2;1234"
            .data => {},
        }

        // Determine our action, which is always a single character.
        const action: u8 = action: {
            const value = self.kv.get('a') orelse break :action 't';
            const c = std.math.cast(u8, value) orelse return error.InvalidFormat;
            break :action c;
        };
        const control: Command.Control = switch (action) {
            'q' => .{ .query = try Transmission.parse(self.kv) },
            't' => .{ .transmit = try Transmission.parse(self.kv) },
            'T' => .{ .transmit_and_display = .{
                .transmission = try Transmission.parse(self.kv),
                .display = try Display.parse(self.kv),
            } },
            'p' => .{ .display = try Display.parse(self.kv) },
            'd' => .{ .delete = try Delete.parse(self.kv) },
            'f' => .{ .transmit_animation_frame = try AnimationFrameLoading.parse(self.kv) },
            'a' => .{ .control_animation = try AnimationControl.parse(self.kv) },
            'c' => .{ .compose_animation = try AnimationFrameComposition.parse(self.kv) },
            else => return error.InvalidFormat,
        };

        // Determine our quiet value
        const quiet: Command.Quiet = if (self.kv.get('q')) |v| quiet: {
            break :quiet switch (v) {
                0 => .no,
                1 => .ok,
                2 => .failures,
                else => return error.InvalidFormat,
            };
        } else .no;

        return .{
            .control = control,
            .quiet = quiet,
            .data = if (self.data.items.len == 0) "" else data: {
                // This is not the most efficient thing to do but it's easy
                // and we can always optimize this later. Images are not super
                // common, especially large ones.
                break :data try alloc.dupe(u8, self.data.items[self.data_i..]);
            },
        };
    }

    fn accumulateValue(self: *CommandParser, c: u8, overflow_state: State) !void {
        const idx = self.kv_temp_len;
        self.kv_temp_len += 1;
        if (self.kv_temp_len > self.kv_temp.len) {
            self.state = overflow_state;
            self.kv_temp_len = 0;
            return;
        }
        self.kv_temp[idx] = c;
    }

    fn finishValue(self: *CommandParser, next_state: State) !void {
        const alloc = self.arena.allocator();

        // We can move states right away, we don't use it.
        self.state = next_state;

        // Check for ASCII chars first
        if (self.kv_temp_len == 1) {
            const c = self.kv_temp[0];
            if (c < '0' or c > '9') {
                try self.kv.put(alloc, self.kv_current, @intCast(c));
                self.kv_temp_len = 0;
                return;
            }
        }

        // Parse the value as a string
        const v = try std.fmt.parseInt(u32, self.kv_temp[0..self.kv_temp_len], 10);
        try self.kv.put(alloc, self.kv_current, v);

        // Clear our temp buffer
        self.kv_temp_len = 0;
    }
};

pub const Command = struct {
    control: Control,
    quiet: Quiet = .no,
    data: []const u8 = "",

    pub const Action = enum {
        query, // q
        transmit, // t
        transmit_and_display, // T
        display, // p
        delete, // d
        transmit_animation_frame, // f
        control_animation, // a
        compose_animation, // c
    };

    pub const Quiet = enum {
        no, // 0
        ok, // 1
        failures, // 2
    };

    pub const Control = union(Action) {
        query: Transmission,
        transmit: Transmission,
        transmit_and_display: struct {
            transmission: Transmission,
            display: Display,
        },
        display: Display,
        delete: Delete,
        transmit_animation_frame: AnimationFrameLoading,
        control_animation: AnimationControl,
        compose_animation: AnimationFrameComposition,
    };

    pub fn deinit(self: Command, alloc: Allocator) void {
        if (self.data.len > 0) alloc.free(self.data);
    }
};

pub const Transmission = struct {
    format: Format = .rgb, // f
    medium: Medium = .direct, // t
    width: u32 = 0, // s
    height: u32 = 0, // v
    size: u32 = 0, // S
    offset: u32 = 0, // O
    image_id: u32 = 0, // i
    image_number: u32 = 0, // I
    placement_id: u32 = 0, // p
    compression: Compression = .none, // o
    more_chunks: bool = false, // m

    pub const Format = enum {
        rgb, // 24
        rgba, // 32
        png, // 100
    };

    pub const Medium = enum {
        direct, // d
        file, // f
        temporary_file, // t
        shared_memory, // s
    };

    pub const Compression = enum {
        none,
        zlib_deflate, // z
    };

    fn parse(kv: KV) !Transmission {
        var result: Transmission = .{};
        if (kv.get('f')) |v| {
            result.format = switch (v) {
                24 => .rgb,
                32 => .rgba,
                100 => .png,
                else => return error.InvalidFormat,
            };
        }

        if (kv.get('t')) |v| {
            const c = std.math.cast(u8, v) orelse return error.InvalidFormat;
            result.medium = switch (c) {
                'd' => .direct,
                'f' => .file,
                't' => .temporary_file,
                's' => .shared_memory,
                else => return error.InvalidFormat,
            };
        }

        if (kv.get('s')) |v| {
            result.width = v;
        }

        if (kv.get('v')) |v| {
            result.height = v;
        }

        if (kv.get('S')) |v| {
            result.size = v;
        }

        if (kv.get('O')) |v| {
            result.offset = v;
        }

        if (kv.get('i')) |v| {
            result.image_id = v;
        }

        if (kv.get('I')) |v| {
            result.image_number = v;
        }

        if (kv.get('p')) |v| {
            result.placement_id = v;
        }

        if (kv.get('o')) |v| {
            const c = std.math.cast(u8, v) orelse return error.InvalidFormat;
            result.compression = switch (c) {
                'z' => .zlib_deflate,
                else => return error.InvalidFormat,
            };
        }

        if (kv.get('m')) |v| {
            result.more_chunks = v > 0;
        }

        return result;
    }
};

pub const Display = struct {
    image_id: u32 = 0, // i
    image_number: u32 = 0, // I
    x: u32 = 0, // x
    y: u32 = 0, // y
    width: u32 = 0, // w
    height: u32 = 0, // h
    x_offset: u32 = 0, // X
    y_offset: u32 = 0, // Y
    columns: u32 = 0, // c
    rows: u32 = 0, // r
    cursor_movement: CursorMovement = .after, // C
    virtual_placement: bool = false, // U
    z: u32 = 0, // z

    pub const CursorMovement = enum {
        after, // 0
        none, // 1
    };

    fn parse(kv: KV) !Display {
        var result: Display = .{};

        if (kv.get('i')) |v| {
            result.image_id = v;
        }

        if (kv.get('I')) |v| {
            result.image_number = v;
        }

        if (kv.get('x')) |v| {
            result.x = v;
        }

        if (kv.get('y')) |v| {
            result.y = v;
        }

        if (kv.get('w')) |v| {
            result.width = v;
        }

        if (kv.get('h')) |v| {
            result.height = v;
        }

        if (kv.get('X')) |v| {
            result.x_offset = v;
        }

        if (kv.get('Y')) |v| {
            result.y_offset = v;
        }

        if (kv.get('c')) |v| {
            result.columns = v;
        }

        if (kv.get('r')) |v| {
            result.rows = v;
        }

        if (kv.get('C')) |v| {
            result.cursor_movement = switch (v) {
                0 => .after,
                1 => .none,
                else => return error.InvalidFormat,
            };
        }

        if (kv.get('U')) |v| {
            result.virtual_placement = switch (v) {
                0 => false,
                1 => true,
                else => return error.InvalidFormat,
            };
        }

        if (kv.get('z')) |v| {
            result.z = v;
        }

        return result;
    }
};

pub const AnimationFrameLoading = struct {
    x: u32 = 0, // x
    y: u32 = 0, // y
    create_frame: u32 = 0, // c
    edit_frame: u32 = 0, // r
    gap_ms: u32 = 0, // z
    composition_mode: CompositionMode = .alpha_blend, // X
    background: Background = .{}, // Y

    pub const Background = packed struct(u32) {
        r: u8 = 0,
        g: u8 = 0,
        b: u8 = 0,
        a: u8 = 0,
    };

    fn parse(kv: KV) !AnimationFrameLoading {
        var result: AnimationFrameLoading = .{};

        if (kv.get('x')) |v| {
            result.x = v;
        }

        if (kv.get('y')) |v| {
            result.y = v;
        }

        if (kv.get('c')) |v| {
            result.create_frame = v;
        }

        if (kv.get('r')) |v| {
            result.edit_frame = v;
        }

        if (kv.get('z')) |v| {
            result.gap_ms = v;
        }

        if (kv.get('X')) |v| {
            result.composition_mode = switch (v) {
                0 => .alpha_blend,
                1 => .overwrite,
                else => return error.InvalidFormat,
            };
        }

        if (kv.get('Y')) |v| {
            result.background = @bitCast(v);
        }

        return result;
    }
};

pub const AnimationFrameComposition = struct {
    frame: u32 = 0, // c
    edit_frame: u32 = 0, // r
    x: u32 = 0, // x
    y: u32 = 0, // y
    width: u32 = 0, // w
    height: u32 = 0, // h
    left_edge: u32 = 0, // X
    top_edge: u32 = 0, // Y
    composition_mode: CompositionMode = .alpha_blend, // C

    fn parse(kv: KV) !AnimationFrameComposition {
        var result: AnimationFrameComposition = .{};

        if (kv.get('c')) |v| {
            result.frame = v;
        }

        if (kv.get('r')) |v| {
            result.edit_frame = v;
        }

        if (kv.get('x')) |v| {
            result.x = v;
        }

        if (kv.get('y')) |v| {
            result.y = v;
        }

        if (kv.get('w')) |v| {
            result.width = v;
        }

        if (kv.get('h')) |v| {
            result.height = v;
        }

        if (kv.get('X')) |v| {
            result.left_edge = v;
        }

        if (kv.get('Y')) |v| {
            result.top_edge = v;
        }

        if (kv.get('C')) |v| {
            result.composition_mode = switch (v) {
                0 => .alpha_blend,
                1 => .overwrite,
                else => return error.InvalidFormat,
            };
        }

        return result;
    }
};

pub const AnimationControl = struct {
    action: AnimationAction = .invalid, // s
    frame: u32 = 0, // r
    gap_ms: u32 = 0, // z
    current_frame: u32 = 0, // c
    loops: u32 = 0, // v

    pub const AnimationAction = enum {
        invalid, // 0
        stop, // 1
        run_wait, // 2
        run, // 3
    };

    fn parse(kv: KV) !AnimationControl {
        var result: AnimationControl = .{};

        if (kv.get('s')) |v| {
            result.action = switch (v) {
                0 => .invalid,
                1 => .stop,
                2 => .run_wait,
                3 => .run,
                else => return error.InvalidFormat,
            };
        }

        if (kv.get('r')) |v| {
            result.frame = v;
        }

        if (kv.get('z')) |v| {
            result.gap_ms = v;
        }

        if (kv.get('c')) |v| {
            result.current_frame = v;
        }

        if (kv.get('v')) |v| {
            result.loops = v;
        }

        return result;
    }
};

pub const Delete = union(enum) {
    // a/A
    all: bool,

    // i/I
    id: struct {
        delete: bool = false, // uppercase
        image_id: u32 = 0, // i
        placement_id: u32 = 0, // p
    },

    // n/N
    newest: struct {
        delete: bool = false, // uppercase
        count: u32 = 0, // I
        placement_id: u32 = 0, // p
    },

    // c/C,
    intersect_cursor: bool,

    // f/F
    animation_frames: bool,

    // p/P
    intersect_cell: struct {
        delete: bool = false, // uppercase
        x: u32 = 0, // x
        y: u32 = 0, // y
    },

    // q/Q
    intersect_cell_z: struct {
        delete: bool = false, // uppercase
        x: u32 = 0, // x
        y: u32 = 0, // y
        z: u32 = 0, // z
    },

    // x/X
    column: struct {
        delete: bool = false, // uppercase
        x: u32 = 0, // x
    },

    // y/Y
    row: struct {
        delete: bool = false, // uppercase
        y: u32 = 0, // y
    },

    // z/Z
    z: struct {
        delete: bool = false, // uppercase
        z: u32 = 0, // z
    },

    fn parse(kv: KV) !Delete {
        const what: u8 = what: {
            const value = kv.get('d') orelse break :what 'a';
            const c = std.math.cast(u8, value) orelse return error.InvalidFormat;
            break :what c;
        };

        return switch (what) {
            'a', 'A' => .{ .all = what == 'A' },

            'i', 'I' => blk: {
                var result: Delete = .{ .id = .{ .delete = what == 'I' } };
                if (kv.get('i')) |v| {
                    result.id.image_id = v;
                }
                if (kv.get('p')) |v| {
                    result.id.placement_id = v;
                }

                break :blk result;
            },

            'n', 'N' => blk: {
                var result: Delete = .{ .newest = .{ .delete = what == 'N' } };
                if (kv.get('I')) |v| {
                    result.newest.count = v;
                }
                if (kv.get('p')) |v| {
                    result.newest.placement_id = v;
                }

                break :blk result;
            },

            'c', 'C' => .{ .intersect_cursor = what == 'C' },

            'f', 'F' => .{ .animation_frames = what == 'F' },

            'p', 'P' => blk: {
                var result: Delete = .{ .intersect_cell = .{ .delete = what == 'P' } };
                if (kv.get('x')) |v| {
                    result.intersect_cell.x = v;
                }
                if (kv.get('y')) |v| {
                    result.intersect_cell.y = v;
                }

                break :blk result;
            },

            'q', 'Q' => blk: {
                var result: Delete = .{ .intersect_cell_z = .{ .delete = what == 'Q' } };
                if (kv.get('x')) |v| {
                    result.intersect_cell_z.x = v;
                }
                if (kv.get('y')) |v| {
                    result.intersect_cell_z.y = v;
                }
                if (kv.get('z')) |v| {
                    result.intersect_cell_z.z = v;
                }

                break :blk result;
            },

            'x', 'X' => blk: {
                var result: Delete = .{ .column = .{ .delete = what == 'X' } };
                if (kv.get('x')) |v| {
                    result.column.x = v;
                }

                break :blk result;
            },

            'y', 'Y' => blk: {
                var result: Delete = .{ .row = .{ .delete = what == 'Y' } };
                if (kv.get('y')) |v| {
                    result.row.y = v;
                }

                break :blk result;
            },

            'z', 'Z' => blk: {
                var result: Delete = .{ .z = .{ .delete = what == 'Z' } };
                if (kv.get('z')) |v| {
                    result.z.z = v;
                }

                break :blk result;
            },

            else => return error.InvalidFormat,
        };
    }
};

pub const CompositionMode = enum {
    alpha_blend, // 0
    overwrite, // 1
};

test "transmission command" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var p = CommandParser.init(alloc);
    defer p.deinit();

    const input = "f=24,s=10,v=20";
    for (input) |c| try p.feed(c);
    const command = try p.complete(alloc);
    defer command.deinit(alloc);

    try testing.expect(command.control == .transmit);
    const v = command.control.transmit;
    try testing.expectEqual(Transmission.Format.rgb, v.format);
    try testing.expectEqual(@as(u32, 10), v.width);
    try testing.expectEqual(@as(u32, 20), v.height);
}

test "query command" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var p = CommandParser.init(alloc);
    defer p.deinit();

    const input = "i=31,s=1,v=1,a=q,t=d,f=24;AAAA";
    for (input) |c| try p.feed(c);
    const command = try p.complete(alloc);
    defer command.deinit(alloc);

    try testing.expect(command.control == .query);
    const v = command.control.query;
    try testing.expectEqual(Transmission.Medium.direct, v.medium);
    try testing.expectEqual(@as(u32, 1), v.width);
    try testing.expectEqual(@as(u32, 1), v.height);
    try testing.expectEqual(@as(u32, 31), v.image_id);
    try testing.expectEqualStrings("AAAA", command.data);
}

test "display command" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var p = CommandParser.init(alloc);
    defer p.deinit();

    const input = "a=p,U=1,i=31,c=80,r=120";
    for (input) |c| try p.feed(c);
    const command = try p.complete(alloc);
    defer command.deinit(alloc);

    try testing.expect(command.control == .display);
    const v = command.control.display;
    try testing.expectEqual(@as(u32, 80), v.columns);
    try testing.expectEqual(@as(u32, 120), v.rows);
    try testing.expectEqual(@as(u32, 31), v.image_id);
}

test "delete command" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var p = CommandParser.init(alloc);
    defer p.deinit();

    const input = "a=d,d=p,x=3,y=4";
    for (input) |c| try p.feed(c);
    const command = try p.complete(alloc);
    defer command.deinit(alloc);

    try testing.expect(command.control == .delete);
    const v = command.control.delete;
    try testing.expect(v == .intersect_cell);
    const dv = v.intersect_cell;
    try testing.expect(!dv.delete);
    try testing.expectEqual(@as(u32, 3), dv.x);
    try testing.expectEqual(@as(u32, 4), dv.y);
}

test "ignore unknown keys (long)" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var p = CommandParser.init(alloc);
    defer p.deinit();

    const input = "f=24,s=10,v=20,hello=world";
    for (input) |c| try p.feed(c);
    const command = try p.complete(alloc);
    defer command.deinit(alloc);

    try testing.expect(command.control == .transmit);
    const v = command.control.transmit;
    try testing.expectEqual(Transmission.Format.rgb, v.format);
    try testing.expectEqual(@as(u32, 10), v.width);
    try testing.expectEqual(@as(u32, 20), v.height);
}

test "ignore very long values" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var p = CommandParser.init(alloc);
    defer p.deinit();

    const input = "f=24,s=10,v=2000000000000000000000000000000000000000";
    for (input) |c| try p.feed(c);
    const command = try p.complete(alloc);
    defer command.deinit(alloc);

    try testing.expect(command.control == .transmit);
    const v = command.control.transmit;
    try testing.expectEqual(Transmission.Format.rgb, v.format);
    try testing.expectEqual(@as(u32, 10), v.width);
    try testing.expectEqual(@as(u32, 0), v.height);
}
