//! Screen represents the internal storage for a terminal screen, including
//! scrollback. This is implemented as a single continuous ring buffer.
//!
//! Definitions:
//!
//!   * Active - The area that is the current edit-able screen.
//!   * History - The area that contains lines from prior input.
//!   * Display - The area that is currently visible to the user. If the
//!       user is scrolled all the way down (latest) then the display
//!       is equivalent to the active area.
//!
const Screen = @This();

// FUTURE: Today this is implemented as a single contiguous ring buffer.
// If we increase the scrollback, we perform a full memory copy. For small
// scrollback, this is pretty cheap. For large (or infinite) scrollback,
// this starts to get pretty nasty. We should change this in the future to
// use a segmented list or something similar. I want to keep all the visible
// area contiguous so its not a simple drop-in. We can take a look at this
// one day.

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const color = @import("color.zig");

const log = std.log.scoped(.screen);

/// A row is a set of cells.
pub const Row = []Cell;

/// Cell is a single cell within the screen.
pub const Cell = struct {
    /// Each cell contains exactly one character. The character is UTF-32
    /// encoded (just the Unicode codepoint).
    char: u32,

    /// Foreground and background color. null means to use the default.
    fg: ?color.RGB = null,
    bg: ?color.RGB = null,

    /// On/off attributes that can be set
    /// TODO: pack it
    attrs: struct {
        bold: u1 = 0,
        underline: u1 = 0,
        inverse: u1 = 0,

        /// If 1, this line is soft-wrapped. Only the last cell in a row
        /// should have this set. The first cell of the next row is actually
        /// part of this row in raw input.
        wrap: u1 = 0,
    } = .{},

    /// True if the cell should be skipped for drawing
    pub fn empty(self: Cell) bool {
        return self.char == 0;
    }
};

pub const RowIterator = struct {
    screen: *const Screen,
    index: usize,

    pub fn next(self: *RowIterator) ?Row {
        if (self.index >= self.screen.rows) return null;
        const res = self.screen.getRow(self.index);
        self.index += 1;
        return res;
    }
};

/// The full list of rows, including any scrollback.
storage: []Cell,

/// The top and bottom of the scroll area. The first visible row if the terminal
/// window were scrolled all the way to the top. The last visible row if the
/// terminal were scrolled all the way to the bottom.
top: usize,
bottom: usize,

/// The offset of the visible area within the storage. This is from the
/// "top" field. So the actual index of the first row is
/// `storage[top + visible_offset]`.
visible_offset: usize,

/// The maximum number of lines that are available in scrollback. This
/// is in addition to the number of visible rows.
max_scrollback: usize,

/// The number of rows and columns in the visible space.
rows: usize,
cols: usize,

/// Initialize a new screen.
pub fn init(
    alloc: Allocator,
    rows: usize,
    cols: usize,
    max_scrollback: usize,
) !Screen {
    // Allocate enough storage to cover every row and column in the visible
    // area. This wastes some up front memory but saves allocations later.
    // TODO: dynamically allocate scrollback
    const buf = try alloc.alloc(Cell, (rows + max_scrollback) * cols);
    std.mem.set(Cell, buf, .{ .char = 0 });

    return Screen{
        .storage = buf,
        .top = 0,
        .bottom = rows,
        .visible_offset = 0,
        .max_scrollback = max_scrollback,
        .rows = rows,
        .cols = cols,
    };
}

pub fn deinit(self: *Screen, alloc: Allocator) void {
    alloc.free(self.storage);
    self.* = undefined;
}

/// This returns true if the display area is anchored at the bottom currently.
pub fn displayIsBottom(self: Screen) bool {
    return self.visible_offset == self.bottomOffset();
}

fn bottomOffset(self: Screen) usize {
    return self.bottom - self.rows;
}

/// Returns an iterator that can be used to iterate over all of the rows
/// from index zero.
pub fn rowIterator(self: *const Screen) RowIterator {
    return .{ .screen = self, .index = 0 };
}

/// Get the visible portion of the screen.
pub fn getVisible(self: Screen) []Cell {
    return self.storage;
}

/// Get a single row in the active area by index (0-indexed).
pub fn getRow(self: Screen, idx: usize) Row {
    // Get the index of the first byte of the the row at index.
    const real_idx = self.rowIndex(idx);

    // The storage is sliced to return exactly the number of columns.
    return self.storage[real_idx .. real_idx + self.cols];
}

/// Get a single cell in the active area. row and col are 0-indexed.
pub fn getCell(self: Screen, row: usize, col: usize) *Cell {
    assert(row < self.rows);
    assert(col < self.cols);
    const row_idx = self.rowIndex(row);
    return &self.storage[row_idx + col];
}

/// Returns the index for the given row (0-indexed) into the underlying
/// storage array.
fn rowIndex(self: Screen, idx: usize) usize {
    assert(idx < self.rows);
    const val = (self.top + self.visible_offset + idx) * self.cols;
    if (val < self.storage.len) return val;
    return val - self.storage.len;
}

/// Scroll behaviors for the scroll function.
pub const Scroll = union(enum) {
    /// Scroll to the top of the scroll buffer. The first line of the
    /// visible display will be the top line of the scroll buffer.
    top: void,

    /// Scroll to the bottom, where the last line of the visible display
    /// will be the last line of the buffer. TODO: are we sure?
    bottom: void,

    /// Scroll up (negative) or down (positive) some fixed amount.
    /// Scrolling direction (up/down) describes the direction the viewport
    /// moves, not the direction text moves. This is the colloquial way that
    /// scrolling is described: "scroll the page down".
    delta: isize,

    /// Same as delta but scrolling down will not grow the scrollback.
    /// Scrolling down at the bottom will do nothing (similar to how
    /// delta at the top does nothing).
    delta_no_grow: isize,
};

/// Scroll the screen by the given behavior. Note that this will always
/// "move" the screen. It is up to the caller to determine if they actually
/// want to do that yet (i.e. are they writing to the end of the screen
/// or not).
pub fn scroll(self: *Screen, behavior: Scroll) void {
    switch (behavior) {
        // Setting display offset to zero makes row 0 be at self.top
        // which is the top!
        .top => self.visible_offset = 0,

        // Calc the bottom by going from top of scrollback (self.top)
        // to the end of the storage, then subtract the number of visible
        // rows.
        .bottom => self.visible_offset = self.bottom - self.rows,

        // TODO: deltas greater than the entire scrollback
        .delta => |delta| self.scrollDelta(delta, true),
        .delta_no_grow => |delta| self.scrollDelta(delta, false),
    }
}

fn scrollDelta(self: *Screen, delta: isize, grow: bool) void {
    // log.info("offsets before: top={} bottom={} visible={}", .{
    //     self.top,
    //     self.bottom,
    //     self.visible_offset,
    // });
    // defer {
    //     log.info("offsets after: top={} bottom={} visible={}", .{
    //         self.top,
    //         self.bottom,
    //         self.visible_offset,
    //     });
    // }

    // If we're scrolling up, then we just subtract and we're done.
    if (delta < 0) {
        self.visible_offset -|= @intCast(usize, -delta);
        return;
    }

    // If we're scrolling down, we have more work to do beacuse we
    // need to determine if we're overwriting our scrollback.
    self.visible_offset +|= @intCast(usize, delta);
    if (grow)
        self.bottom +|= @intCast(usize, delta)
    else {
        // If we're not growing, then we want to ensure we don't scroll
        // off the bottom. Calculate the number of rows we can see. If we
        // can see less than the number of rows we have available, then scroll
        // back a bit.
        const visible_bottom = self.visible_offset + self.rows;
        if (visible_bottom > self.bottom) {
            self.visible_offset = self.bottom - self.rows;

            // We can also fast-track this case because we know we won't
            // be overlapping at all so we can return immediately.
            return;
        }
    }

    // TODO: can optimize scrollback = 0

    // Determine if we need to clear rows.
    assert(@mod(self.storage.len, self.cols) == 0);
    const storage_rows = self.storage.len / self.cols;
    const visible_zero = self.top + self.visible_offset;
    const rows_overlapped = if (visible_zero >= storage_rows) overlap: {
        // We're wrapping from the top of the visible area. In this
        // scenario, we just check that we have enough space from
        // our true visible top to zero.
        const visible_top = visible_zero - storage_rows;
        const rows_available = self.top - visible_top;
        if (rows_available >= self.rows) return;

        // We overlap our missing rows
        break :overlap self.rows - rows_available;
    } else overlap: {
        // First check: if we have enough space in the storage buffer
        // FORWARD to accomodate all our rows, then we're fine.
        const rows_forward = storage_rows - (self.top + self.visible_offset);
        if (rows_forward >= self.rows) return;

        // Second check: if we have enough space PRIOR to zero when
        // wrapped, then we're fine.
        const rows_wrapped = self.rows - rows_forward;
        if (rows_wrapped < self.top) return;

        // We need to clear the rows in the overlap and move the top
        // of the scrollback buffer.
        break :overlap rows_wrapped - self.top;
    };

    // If we are growing, then we clear the overlap and reset zero
    if (grow) {
        // Clear our overlap
        const clear_start = self.top * self.cols;
        const clear_end = clear_start + (rows_overlapped * self.cols);
        std.mem.set(Cell, self.storage[clear_start..clear_end], .{ .char = 0 });

        // Move to accomodate overlap. This deletes scrollback.
        self.top = @mod(self.top + rows_overlapped, storage_rows);

        // The new bottom is right up against the new top since we're using
        // the full buffer. The bottom is therefore the full size of the storage.
        self.bottom = storage_rows;
    }

    // Move back the number of overlapped
    self.visible_offset -= rows_overlapped;
}

/// Copy row at src to dst.
pub fn copyRow(self: *Screen, dst: usize, src: usize) void {
    const src_row = self.getRow(src);
    const dst_row = self.getRow(dst);
    std.mem.copy(Cell, dst_row, src_row);
}

/// Resize the screen. The rows or cols can be bigger or smaller. Due to
/// the internal representation of a screen, this usually involves a significant
/// amount of copying compared to any other operations.
///
/// This will trim data if the size is getting smaller. It is expected that
/// callers will reflow the text prior to calling this.
pub fn resize(self: *Screen, alloc: Allocator, rows: usize, cols: usize) !void {
    // Make a copy so we can access the old indexes.
    const old = self.*;

    // Reallocate the storage
    self.storage = try alloc.alloc(Cell, (rows + self.max_scrollback) * cols);
    self.top = 0;
    self.bottom = rows;
    self.rows = rows;
    self.cols = cols;

    // TODO: reflow due to soft wrap

    // If we're increasing height, then copy all rows (start at 0).
    // Otherwise start at the latest row that includes the bottom row,
    // aka strip the top.
    var y: usize = if (rows >= old.rows) 0 else old.rows - rows;
    const start = y;
    const col_end = @minimum(old.cols, cols);
    while (y < old.rows) : (y += 1) {
        // Copy the old row into the new row, just losing the columsn
        // if we got thinner.
        const old_row = old.getRow(y);
        const new_row = self.getRow(y - start);
        std.mem.copy(Cell, new_row, old_row[0..col_end]);

        // If our new row is wider, then we copy zeroes into the rest.
        if (new_row.len > old_row.len) {
            std.mem.set(Cell, new_row[old_row.len..], .{ .char = 0 });
        }
    }

    // If we grew rows, then set the remaining data to zero.
    if (rows > old.rows) {
        std.mem.set(Cell, self.storage[self.rowIndex(old.rows)..], .{ .char = 0 });
    }

    // Free the old data
    alloc.free(old.storage);
}

/// Turns the screen into a string.
pub fn testString(self: Screen, alloc: Allocator) ![]const u8 {
    const buf = try alloc.alloc(u8, self.storage.len + self.rows);

    var i: usize = 0;
    var y: usize = 0;
    var rows = self.rowIterator();
    while (rows.next()) |row| {
        defer y += 1;

        if (y > 0) {
            buf[i] = '\n';
            i += 1;
        }

        for (row) |cell| {
            // TODO: handle character after null
            if (cell.char > 0) {
                i += try std.unicode.utf8Encode(@intCast(u21, cell.char), buf[i..]);
            }
        }
    }

    // Never render the final newline
    const str = std.mem.trimRight(u8, buf[0..i], "\n");
    return try alloc.realloc(buf, str.len);
}

/// Writes a basic string into the screen for testing. Newlines (\n) separate
/// each row.
fn testWriteString(self: *Screen, text: []const u8) void {
    var y: usize = 0;
    var x: usize = 0;
    var row = self.getRow(y);
    for (text) |c| {
        if (c == '\n') {
            y += 1;
            x = 0;
            row = self.getRow(y);
            continue;
        }

        assert(x < self.cols);
        row[x].char = @intCast(u32, c);
        x += 1;
    }
}

test "Screen" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s = try init(alloc, 3, 5, 0);
    defer s.deinit(alloc);

    // Sanity check that our test helpers work
    const str = "1ABCD\n2EFGH\n3IJKL";
    s.testWriteString(str);
    var contents = try s.testString(alloc);
    defer alloc.free(contents);
    try testing.expectEqualStrings(str, contents);

    // Test the row iterator
    var count: usize = 0;
    var iter = s.rowIterator();
    while (iter.next()) |row| {
        // Rows should be pointer equivalent to getRow
        const row_other = s.getRow(count);
        try testing.expectEqual(row.ptr, row_other.ptr);
        count += 1;
    }

    // Should go through all rows
    try testing.expectEqual(@as(usize, 3), count);
}

test "Screen: scrolling" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s = try init(alloc, 3, 5, 0);
    defer s.deinit(alloc);
    s.testWriteString("1ABCD\n2EFGH\n3IJKL");

    try testing.expect(s.displayIsBottom());

    // Scroll down, should still be bottom
    s.scroll(.{ .delta = 1 });
    try testing.expect(s.displayIsBottom());

    // Test our row index
    try testing.expectEqual(@as(usize, 5), s.rowIndex(0));
    try testing.expectEqual(@as(usize, 10), s.rowIndex(1));
    try testing.expectEqual(@as(usize, 0), s.rowIndex(2));

    {
        // Test our contents rotated
        var contents = try s.testString(alloc);
        defer alloc.free(contents);
        try testing.expectEqualStrings("2EFGH\n3IJKL", contents);
    }

    // Scrolling to the bottom does nothing
    s.scroll(.{ .bottom = {} });

    {
        // Test our contents rotated
        var contents = try s.testString(alloc);
        defer alloc.free(contents);
        try testing.expectEqualStrings("2EFGH\n3IJKL", contents);
    }
}

test "Screen: scroll down from 0" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s = try init(alloc, 3, 5, 0);
    defer s.deinit(alloc);
    s.testWriteString("1ABCD\n2EFGH\n3IJKL");
    s.scroll(.{ .delta = -1 });
    try testing.expect(s.displayIsBottom());

    {
        // Test our contents rotated
        var contents = try s.testString(alloc);
        defer alloc.free(contents);
        try testing.expectEqualStrings("1ABCD\n2EFGH\n3IJKL", contents);
    }
}

test "Screen: scrollback" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s = try init(alloc, 3, 5, 1);
    defer s.deinit(alloc);
    s.testWriteString("1ABCD\n2EFGH\n3IJKL");
    s.scroll(.{ .delta = 1 });

    // Test our row index
    try testing.expectEqual(@as(usize, 5), s.rowIndex(0));
    try testing.expectEqual(@as(usize, 10), s.rowIndex(1));
    try testing.expectEqual(@as(usize, 15), s.rowIndex(2));

    {
        // Test our contents rotated
        var contents = try s.testString(alloc);
        defer alloc.free(contents);
        try testing.expectEqualStrings("2EFGH\n3IJKL", contents);
    }

    // Scrolling to the bottom
    s.scroll(.{ .bottom = {} });
    try testing.expect(s.displayIsBottom());

    {
        // Test our contents rotated
        var contents = try s.testString(alloc);
        defer alloc.free(contents);
        try testing.expectEqualStrings("2EFGH\n3IJKL", contents);
    }

    // Scrolling back should make it visible again
    s.scroll(.{ .delta = -1 });
    try testing.expect(!s.displayIsBottom());

    {
        // Test our contents rotated
        var contents = try s.testString(alloc);
        defer alloc.free(contents);
        try testing.expectEqualStrings("1ABCD\n2EFGH\n3IJKL", contents);
    }

    // Scrolling back again should do nothing
    s.scroll(.{ .delta = -1 });

    {
        // Test our contents rotated
        var contents = try s.testString(alloc);
        defer alloc.free(contents);
        try testing.expectEqualStrings("1ABCD\n2EFGH\n3IJKL", contents);
    }

    // Scrolling to the bottom
    s.scroll(.{ .bottom = {} });

    {
        // Test our contents rotated
        var contents = try s.testString(alloc);
        defer alloc.free(contents);
        try testing.expectEqualStrings("2EFGH\n3IJKL", contents);
    }

    // Scrolling forward with no grow should do nothing
    s.scroll(.{ .delta_no_grow = 1 });

    {
        // Test our contents rotated
        var contents = try s.testString(alloc);
        defer alloc.free(contents);
        try testing.expectEqualStrings("2EFGH\n3IJKL", contents);
    }

    // Scrolling to the top should work
    s.scroll(.{ .top = {} });

    {
        // Test our contents rotated
        var contents = try s.testString(alloc);
        defer alloc.free(contents);
        try testing.expectEqualStrings("1ABCD\n2EFGH\n3IJKL", contents);
    }
}

test "Screen: scrollback empty" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s = try init(alloc, 3, 5, 50);
    defer s.deinit(alloc);
    s.testWriteString("1ABCD\n2EFGH\n3IJKL");
    s.scroll(.{ .delta_no_grow = 1 });

    {
        // Test our contents
        var contents = try s.testString(alloc);
        defer alloc.free(contents);
        try testing.expectEqualStrings("1ABCD\n2EFGH\n3IJKL", contents);
    }
}

test "Screen: row copy" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s = try init(alloc, 3, 5, 0);
    defer s.deinit(alloc);
    s.testWriteString("1ABCD\n2EFGH\n3IJKL");

    // Copy
    s.scroll(.{ .delta = 1 });
    s.copyRow(2, 0);

    // Test our contents
    var contents = try s.testString(alloc);
    defer alloc.free(contents);
    try testing.expectEqualStrings("2EFGH\n3IJKL\n2EFGH", contents);
}

test "Screen: resize more rows" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s = try init(alloc, 3, 5, 0);
    defer s.deinit(alloc);
    const str = "1ABCD\n2EFGH\n3IJKL";
    s.testWriteString(str);
    try s.resize(alloc, 10, 5);

    {
        var contents = try s.testString(alloc);
        defer alloc.free(contents);
        try testing.expectEqualStrings(str, contents);
    }
}

test "Screen: resize less rows" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s = try init(alloc, 3, 5, 0);
    defer s.deinit(alloc);
    const str = "1ABCD\n2EFGH\n3IJKL";
    s.testWriteString(str);
    try s.resize(alloc, 2, 5);

    {
        var contents = try s.testString(alloc);
        defer alloc.free(contents);
        try testing.expectEqualStrings("2EFGH\n3IJKL", contents);
    }
}

test "Screen: resize more cols" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s = try init(alloc, 3, 5, 0);
    defer s.deinit(alloc);
    const str = "1ABCD\n2EFGH\n3IJKL";
    s.testWriteString(str);
    try s.resize(alloc, 3, 10);

    {
        var contents = try s.testString(alloc);
        defer alloc.free(contents);
        try testing.expectEqualStrings(str, contents);
    }
}

test "Screen: resize less cols" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s = try init(alloc, 3, 5, 0);
    defer s.deinit(alloc);
    const str = "1ABCD\n2EFGH\n3IJKL";
    s.testWriteString(str);
    try s.resize(alloc, 3, 4);

    {
        var contents = try s.testString(alloc);
        defer alloc.free(contents);
        const expected = "1ABC\n2EFG\n3IJK";
        try testing.expectEqualStrings(expected, contents);
    }
}
