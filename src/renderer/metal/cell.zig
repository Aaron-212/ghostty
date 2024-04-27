const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const renderer = @import("../../renderer.zig");
const terminal = @import("../../terminal/main.zig");
const mtl_shaders = @import("shaders.zig");

/// The possible cell content keys that exist.
pub const Key = enum {
    bg,
    text,
    underline,
    strikethrough,

    /// Returns the GPU vertex type for this key.
    fn CellType(self: Key) type {
        return switch (self) {
            .bg => mtl_shaders.CellBg,

            .text,
            .underline,
            .strikethrough,
            => mtl_shaders.CellText,
        };
    }
};

/// The contents of all the cells in the terminal.
pub const Contents = struct {
    /// The map contains the mapping of cell content for every cell in the
    /// terminal to the index in the cells array that the content is at.
    /// This is ALWAYS sized to exactly (rows * cols) so we want to keep
    /// this as small as possible.
    ///
    /// Before any operation, this must be initialized by calling resize
    /// on the contents.
    map: []Map = undefined,

    /// The grid size of the terminal. This is used to determine the
    /// map array index from a coordinate.
    cols: usize = 0,

    /// The actual GPU data (on the CPU) for all the cells in the terminal.
    /// This only contains the cells that have content set. To determine
    /// if a cell has content set, we check the map.
    ///
    /// This data is synced to a buffer on every frame.
    bgs: std.ArrayListUnmanaged(mtl_shaders.CellBg) = .{},
    text: std.ArrayListUnmanaged(mtl_shaders.CellText) = .{},

    pub fn deinit(self: *Contents, alloc: Allocator) void {
        alloc.free(self.map);
        self.bgs.deinit(alloc);
        self.text.deinit(alloc);
    }

    /// Resize the cell contents for the given grid size. This will
    /// always invalidate the entire cell contents.
    pub fn resize(
        self: *Contents,
        alloc: Allocator,
        size: renderer.GridSize,
    ) !void {
        const map = try alloc.alloc(Map, size.rows * size.columns);
        errdefer alloc.free(map);
        @memset(map, .{});

        alloc.free(self.map);
        self.map = map;
        self.cols = size.columns;
        self.bgs.clearAndFree(alloc);
        self.text.clearAndFree(alloc);
    }

    /// Get the cell contents for the given type and coordinate.
    pub fn get(
        self: *const Contents,
        comptime key: Key,
        coord: terminal.Coordinate,
    ) ?key.CellType() {
        const idx = coord.y * self.cols + coord.x;
        const mapping = self.map[idx].array.get(key);
        if (!mapping.set) return null;
        return switch (key) {
            .bg => self.bgs.items[mapping.index],

            .text,
            .underline,
            .strikethrough,
            => self.text.items[mapping.index],
        };
    }

    /// Set the cell contents for a given type of content at a given
    /// coordinate (provided by the celll contents).
    pub fn set(
        self: *Contents,
        alloc: Allocator,
        comptime key: Key,
        cell: key.CellType(),
    ) !void {
        const mapping = self.map[
            self.index(.{
                .x = cell.grid_pos[0],
                .y = cell.grid_pos[1],
            })
        ].array.getPtr(key);

        // Get our list of cells based on the key (comptime).
        const list = &@field(self, switch (key) {
            .bg => "bgs",
            .text, .underline, .strikethrough => "text",
        });

        // If this content type is already set on this cell, we can
        // simply update the pre-existing index in the list to the new
        // contents.
        if (mapping.set) {
            list.items[mapping.index] = cell;
            return;
        }

        // Otherwise we need to append the new cell to the list.
        const idx: u31 = @intCast(list.items.len);
        try list.append(alloc, cell);
        mapping.* = .{ .set = true, .index = idx };
    }

    /// Clear all of the cell contents for a given row.
    pub fn clear(
        self: *Contents,
        y: usize,
    ) void {
        const start_idx = y * self.cols;
        const end_idx = start_idx + self.cols;
        const maps = self.map[start_idx..end_idx];
        for (maps) |*map| {
            var it = map.array.iterator();
            while (it.next()) |entry| {
                if (!entry.value.set) continue;

                // This value is no longer set
                entry.value.set = false;

                // Remove the value at index. This does a "swap remove"
                // which swaps the last element in to this place. This is
                // important because after this we need to update the mapping
                // for the swapped element.
                const original_index = entry.value.index;
                const coord_: ?terminal.Coordinate = switch (entry.key) {
                    .bg => bg: {
                        _ = self.bgs.swapRemove(original_index);
                        if (self.bgs.items.len == original_index) break :bg null;
                        const new = self.bgs.items[original_index];
                        break :bg .{ .x = new.grid_pos[0], .y = new.grid_pos[1] };
                    },

                    .text,
                    .underline,
                    .strikethrough,
                    => text: {
                        _ = self.text.swapRemove(original_index);
                        if (self.text.items.len == original_index) break :text null;
                        const new = self.text.items[original_index];
                        break :text .{ .x = new.grid_pos[0], .y = new.grid_pos[1] };
                    },
                };

                // If we have the coordinate of the swapped element, then
                // we need to update it to point at its new index, which is
                // the index of the element we just removed.
                //
                // The reason we wouldn't have a coordinate is if we are
                // removing the last element in the array, then nothing
                // is swapped in and nothing needs to be updated.
                if (coord_) |coord| {
                    const old_index = switch (entry.key) {
                        .bg => self.bgs.items.len,
                        .text, .underline, .strikethrough => self.text.items.len,
                    };
                    var old_it = self.map[self.index(coord)].array.iterator();
                    while (old_it.next()) |old_entry| {
                        if (old_entry.value.set and
                            old_entry.value.index == old_index)
                        {
                            old_entry.value.index = original_index;
                            break;
                        }
                    }
                }
            }
        }
    }

    fn index(self: *const Contents, coord: terminal.Coordinate) usize {
        return coord.y * self.cols + coord.x;
    }

    /// Structures related to the contents of the cell.
    const Map = struct {
        /// The set of cell content mappings for a given cell for every
        /// possible key. This is used to determine if a cell has a given
        /// type of content (i.e. an underlyine styling) and if so what index
        /// in the cells array that content is at.
        const Array = std.EnumArray(Key, Mapping);

        /// The mapping for a given key consists of a bit indicating if the
        /// content is set and the index in the cells array that the content
        /// is at. We pack this into a 32-bit integer so we only use 4 bytes
        /// per possible cell content type.
        const Mapping = packed struct(u32) {
            set: bool = false,
            index: u31 = 0,
        };

        /// The backing array of mappings.
        array: Array = Array.initFill(.{}),

        pub fn empty(self: *Map) bool {
            var it = self.array.iterator();
            while (it.next()) |entry| {
                if (entry.value.set) return false;
            }

            return true;
        }
    };
};

test Contents {
    const testing = std.testing;
    const alloc = testing.allocator;

    const rows = 10;
    const cols = 10;

    var c: Contents = .{};
    try c.resize(alloc, .{ .rows = rows, .columns = cols });
    defer c.deinit(alloc);

    // Assert that get returns null for everything.
    for (0..rows) |y| {
        for (0..cols) |x| {
            try testing.expect(c.get(.bg, .{
                .x = @intCast(x),
                .y = @intCast(y),
            }) == null);
        }
    }

    // Set some contents
    const cell: mtl_shaders.CellBg = .{
        .mode = .rgb,
        .grid_pos = .{ 4, 1 },
        .cell_width = 1,
        .color = .{ 0, 0, 0, 1 },
    };
    try c.set(alloc, .bg, cell);
    try testing.expectEqual(cell, c.get(.bg, .{ .x = 4, .y = 1 }).?);

    // Can clear it
    c.clear(1);
    for (0..rows) |y| {
        for (0..cols) |x| {
            try testing.expect(c.get(.bg, .{
                .x = @intCast(x),
                .y = @intCast(y),
            }) == null);
        }
    }
}

test "Contents clear retains other content" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const rows = 10;
    const cols = 10;

    var c: Contents = .{};
    try c.resize(alloc, .{ .rows = rows, .columns = cols });
    defer c.deinit(alloc);

    // Set some contents
    const cell1: mtl_shaders.CellBg = .{
        .mode = .rgb,
        .grid_pos = .{ 4, 1 },
        .cell_width = 1,
        .color = .{ 0, 0, 0, 1 },
    };
    const cell2: mtl_shaders.CellBg = .{
        .mode = .rgb,
        .grid_pos = .{ 4, 2 },
        .cell_width = 1,
        .color = .{ 0, 0, 0, 1 },
    };
    try c.set(alloc, .bg, cell1);
    try c.set(alloc, .bg, cell2);
    c.clear(1);

    // Row 2 should still be valid.
    try testing.expectEqual(cell2, c.get(.bg, .{ .x = 4, .y = 2 }).?);
}

test "Contents clear last added content" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const rows = 10;
    const cols = 10;

    var c: Contents = .{};
    try c.resize(alloc, .{ .rows = rows, .columns = cols });
    defer c.deinit(alloc);

    // Set some contents
    const cell1: mtl_shaders.CellBg = .{
        .mode = .rgb,
        .grid_pos = .{ 4, 1 },
        .cell_width = 1,
        .color = .{ 0, 0, 0, 1 },
    };
    const cell2: mtl_shaders.CellBg = .{
        .mode = .rgb,
        .grid_pos = .{ 4, 2 },
        .cell_width = 1,
        .color = .{ 0, 0, 0, 1 },
    };
    try c.set(alloc, .bg, cell1);
    try c.set(alloc, .bg, cell2);
    c.clear(2);

    // Row 2 should still be valid.
    try testing.expectEqual(cell1, c.get(.bg, .{ .x = 4, .y = 1 }).?);
}

test "Contents.Map size" {
    // We want to be mindful of when this increases because it affects
    // renderer memory significantly.
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Contents.Map));
}
