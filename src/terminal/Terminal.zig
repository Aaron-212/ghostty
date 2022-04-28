//! The primary terminal emulation structure. This represents a single
//! "terminal" containing a grid of characters and exposes various operations
//! on that grid. This also maintains the scrollback buffer.
const Terminal = @This();

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ansi = @import("ansi.zig");
const Parser = @import("Parser.zig");
const Tabstops = @import("Tabstops.zig");

const log = std.log.scoped(.terminal);

/// Screen is the current screen state.
screen: Screen,

/// Cursor position.
cursor: Cursor,

/// Where the tabstops are.
tabstops: Tabstops,

/// The size of the terminal.
rows: usize,
cols: usize,

/// VT stream parser
parser: Parser,

/// Screen represents a presentable terminal screen made up of lines and cells.
const Screen = std.ArrayListUnmanaged(Line);
const Line = std.ArrayListUnmanaged(Cell);

/// Cell is a single cell within the terminal.
const Cell = struct {
    /// Each cell contains exactly one character. The character is UTF-8 encoded.
    char: u32,

    // TODO(mitchellh): this is where we'll track fg/bg and other attrs.

    /// True if the cell should be skipped for drawing
    pub fn empty(self: Cell) bool {
        return self.char == 0;
    }
};

/// Cursor represents the cursor state.
const Cursor = struct {
    x: usize,
    y: usize,
};

/// Initialize a new terminal.
pub fn init(alloc: Allocator, cols: usize, rows: usize) !Terminal {
    return Terminal{
        .cols = cols,
        .rows = rows,
        .screen = .{},
        .cursor = .{ .x = 0, .y = 0 },
        .tabstops = try Tabstops.init(alloc, cols, 8),
        .parser = Parser.init(),
    };
}

pub fn deinit(self: *Terminal, alloc: Allocator) void {
    self.tabstops.deinit(alloc);
    for (self.screen.items) |*line| line.deinit(alloc);
    self.screen.deinit(alloc);
    self.* = undefined;
}

/// Resize the underlying terminal.
pub fn resize(self: *Terminal, cols: usize, rows: usize) void {
    // TODO: actually doing anything for this
    self.cols = cols;
    self.rows = rows;
}

/// Return the current string value of the terminal. Newlines are
/// encoded as "\n". This omits any formatting such as fg/bg.
///
/// The caller must free the string.
pub fn plainString(self: Terminal, alloc: Allocator) ![]const u8 {
    // Create a buffer that has the number of lines we have times the maximum
    // width it could possibly be. In all likelihood we aren't using the full
    // width (of at least the last line) but the error margine here won't be
    // much.
    const buffer = try alloc.alloc(u8, self.screen.items.len * self.cols * 4);
    var i: usize = 0;
    for (self.screen.items) |line, y| {
        if (y > 0) {
            buffer[i] = '\n';
            i += 1;
        }

        for (line.items) |cell| {
            i += try std.unicode.utf8Encode(@intCast(u21, cell.char), buffer[i..]);
        }
    }

    return buffer[0..i];
}

/// Append a string of characters. See appendChar.
pub fn append(self: *Terminal, alloc: Allocator, str: []const u8) !void {
    for (str) |c| {
        try self.appendChar(alloc, c);
    }
}

/// Append a single character to the terminal.
///
/// This may allocate if necessary to store the character in the grid.
pub fn appendChar(self: *Terminal, alloc: Allocator, c: u8) !void {
    log.debug("char: {}", .{c});
    const actions = self.parser.next(c);
    for (actions) |action_opt| {
        switch (action_opt orelse continue) {
            .print => |p| try self.print(alloc, p),
            .execute => |code| try self.execute(alloc, code),
        }
    }
}

fn print(self: *Terminal, alloc: Allocator, c: u8) !void {
    // Build our cell
    const cell = try self.getOrPutCell(alloc, self.cursor.x, self.cursor.y);
    cell.* = .{
        .char = @intCast(u32, c),
    };

    // Move the cursor
    self.cursor.x += 1;
}

fn execute(self: *Terminal, alloc: Allocator, c: u8) !void {
    switch (@intToEnum(ansi.C0, c)) {
        .BEL => self.bell(),
        .BS => self.backspace(),
        .HT => try self.horizontal_tab(alloc),
        .LF => self.linefeed(),
        .CR => self.carriage_return(),
    }
}

pub fn bell(self: *Terminal) void {
    // TODO: bell
    _ = self;
    log.info("bell", .{});
}

/// Backspace moves the cursor back a column (but not less than 0).
pub fn backspace(self: *Terminal) void {
    self.cursor.x -|= 1;
}

/// Horizontal tab moves the cursor to the next tabstop, clearing
/// the screen to the left the tabstop.
pub fn horizontal_tab(self: *Terminal, alloc: Allocator) !void {
    while (self.cursor.x < self.cols) {
        // Clear
        try self.print(alloc, ' ');

        // If the last cursor position was a tabstop we return. We do
        // "last cursor position" because we want a space to be written
        // at the tabstop unless we're at the end (the while condition).
        if (self.tabstops.get(self.cursor.x - 1)) return;
    }
}

/// Carriage return moves the cursor to the first column.
pub fn carriage_return(self: *Terminal) void {
    self.cursor.x = 0;
}

/// Linefeed moves the cursor to the next line.
pub fn linefeed(self: *Terminal) void {
    // TODO: end of screen
    self.cursor.y += 1;
}

fn getOrPutCell(self: *Terminal, alloc: Allocator, x: usize, y: usize) !*Cell {
    // If we don't have enough lines to get to y, then add it.
    if (self.screen.items.len < y + 1) {
        try self.screen.ensureTotalCapacity(alloc, y + 1);
        self.screen.appendNTimesAssumeCapacity(.{}, y + 1 - self.screen.items.len);
    }

    const line = &self.screen.items[y];
    if (line.items.len < x + 1) {
        try line.ensureTotalCapacity(alloc, x + 1);
        line.appendNTimesAssumeCapacity(undefined, x + 1 - line.items.len);
    }

    return &line.items[x];
}

test {
    _ = Parser;
    _ = Tabstops;
}

test "Terminal: input with no control characters" {
    var t = try init(testing.allocator, 80, 80);
    defer t.deinit(testing.allocator);

    // Basic grid writing
    try t.append(testing.allocator, "hello");
    try testing.expectEqual(@as(usize, 0), t.cursor.y);
    try testing.expectEqual(@as(usize, 5), t.cursor.x);
    {
        var str = try t.plainString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("hello", str);
    }
}

test "Terminal: C0 control LF and CR" {
    var t = try init(testing.allocator, 80, 80);
    defer t.deinit(testing.allocator);

    // Basic grid writing
    try t.append(testing.allocator, "hello\r\nworld");
    try testing.expectEqual(@as(usize, 1), t.cursor.y);
    try testing.expectEqual(@as(usize, 5), t.cursor.x);
    {
        var str = try t.plainString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("hello\nworld", str);
    }
}

test "Terminal: C0 control BS" {
    var t = try init(testing.allocator, 80, 80);
    defer t.deinit(testing.allocator);

    // BS
    try t.append(testing.allocator, "hello");
    try t.appendChar(testing.allocator, @enumToInt(ansi.C0.BS));
    try t.append(testing.allocator, "y");
    try testing.expectEqual(@as(usize, 0), t.cursor.y);
    try testing.expectEqual(@as(usize, 5), t.cursor.x);
    {
        var str = try t.plainString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("helly", str);
    }
}

test "Terminal: horizontal tabs" {
    var t = try init(testing.allocator, 80, 5);
    defer t.deinit(testing.allocator);

    // HT
    try t.append(testing.allocator, "1\t");
    try testing.expectEqual(@as(usize, 8), t.cursor.x);

    // HT
    try t.append(testing.allocator, "\t");
    try testing.expectEqual(@as(usize, 16), t.cursor.x);
}
