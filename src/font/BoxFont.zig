//! This file contains functions for drawing the box drawing characters
//! (https://en.wikipedia.org/wiki/Box-drawing_character) and related
//! characters that are provided by the terminal.
const BoxFont = @This();

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const pixman = @import("pixman");
const font = @import("main.zig");
const Atlas = @import("../Atlas.zig");

const log = std.log.scoped(.box_font);

/// The cell width and height because the boxes are fit perfectly
/// into a cell so that they all properly connect with zero spacing.
width: u32,
height: u32,

/// Base thickness value for lines of the box. This is in pixels. If you
/// want to do any DPI scaling, it is expected to be done earlier.
thickness: u32,

/// We use alpha-channel-only images for the box font so white causes
/// a pixel to be shown.
const white: pixman.Color = .{
    .red = 0xFFFF,
    .green = 0xFFFF,
    .blue = 0xFFFF,
    .alpha = 0xFFFF,
};

/// The thickness of a line.
const Thickness = enum {
    light,
    heavy,

    /// Calculate the real height of a line based on its thickness
    /// and a base thickness value. The base thickness value is expected
    /// to be in pixels.
    fn height(self: Thickness, base: u32) u32 {
        return switch (self) {
            .light => base,
            .heavy => base * 3,
        };
    }
};

pub fn renderGlyph(
    self: BoxFont,
    alloc: Allocator,
    atlas: *Atlas,
    cp: u32,
) !font.Glyph {
    assert(atlas.format == .greyscale);

    // Determine the config for our image buffer. The images we draw
    // for boxes are always 8bpp
    const format: pixman.FormatCode = .a8;
    const stride = format.strideForWidth(self.width);
    const len = @intCast(usize, stride * @intCast(c_int, self.height));

    // Allocate our buffer
    var data = try alloc.alloc(u32, len);
    defer alloc.free(data);
    std.mem.set(u32, data, 0);

    // Create the image we'll draw to
    const img = try pixman.Image.createBitsNoClear(
        format,
        @intCast(c_int, self.width),
        @intCast(c_int, self.height),
        data.ptr,
        stride,
    );
    defer _ = img.unref();

    try self.draw(img, cp);

    // Reserve our region in the atlas and render the glyph to it.
    const region = try atlas.reserve(alloc, self.width, self.height);
    if (region.width > 0 and region.height > 0) {
        // Convert our []u32 to []u8 since we use 8bpp formats
        assert(format.bpp() == 8);
        const len_u8 = len * 4;
        const data_u8 = @alignCast(@alignOf(u8), @ptrCast([*]u8, data.ptr)[0..len_u8]);

        const depth = atlas.format.depth();

        // We can avoid a buffer copy if our atlas width and bitmap
        // width match and the bitmap pitch is just the width (meaning
        // the data is tightly packed).
        const needs_copy = !(self.width * depth == stride);

        // If we need to copy the data, we copy it into a temporary buffer.
        const buffer = if (needs_copy) buffer: {
            var temp = try alloc.alloc(u8, self.width * self.height * depth);
            var dst_ptr = temp;
            var src_ptr = data_u8.ptr;
            var i: usize = 0;
            while (i < self.height) : (i += 1) {
                std.mem.copy(u8, dst_ptr, src_ptr[0 .. self.width * depth]);
                dst_ptr = dst_ptr[self.width * depth ..];
                src_ptr += @intCast(usize, stride);
            }
            break :buffer temp;
        } else data_u8[0..(self.width * self.height * depth)];
        defer if (buffer.ptr != data_u8.ptr) alloc.free(buffer);

        // Write the glyph information into the atlas
        assert(region.width == self.width);
        assert(region.height == self.height);
        atlas.set(region, buffer);
    }

    // Our coordinates start at the BOTTOM for our renderers so we have to
    // specify an offset of the full height because we rendered a full size
    // cell.
    const offset_y = @intCast(i32, self.height);

    return font.Glyph{
        .width = self.width,
        .height = self.height,
        .offset_x = 0,
        .offset_y = offset_y,
        .atlas_x = region.x,
        .atlas_y = region.y,
        .advance_x = @intToFloat(f32, self.width),
    };
}

fn draw(self: BoxFont, img: *pixman.Image, cp: u32) !void {
    switch (cp) {
        0x2500 => self.draw_box_drawings_light_horizontal(img),
        0x2501 => self.draw_box_drawings_heavy_horizontal(img),
        0x2502 => self.draw_box_drawings_light_vertical(img),
        0x2503 => self.draw_box_drawings_heavy_vertical(img),
        // 0x2504 => self.draw_box_drawings_light_triple_dash_horizontal(img),
        // 0x2505 => self.draw_box_drawings_heavy_triple_dash_horizontal(img),
        // 0x2506 => self.draw_box_drawings_light_triple_dash_vertical(img),
        // 0x2507 => self.draw_box_drawings_heavy_triple_dash_vertical(img),
        // 0x2508 => self.draw_box_drawings_light_quadruple_dash_horizontal(img),
        // 0x2509 => self.draw_box_drawings_heavy_quadruple_dash_horizontal(img),
        // 0x250a => self.draw_box_drawings_light_quadruple_dash_vertical(img),
        // 0x250b => self.draw_box_drawings_heavy_quadruple_dash_vertical(img),
        // 0x250c => self.draw_box_drawings_light_down_and_right(img),
        // 0x250d => self.draw_box_drawings_down_light_and_right_heavy(img),
        // 0x250e => self.draw_box_drawings_down_heavy_and_right_light(img),
        // 0x250f => self.draw_box_drawings_heavy_down_and_right(img),
        else => return error.InvalidCodepoint,
    }
}

fn draw_box_drawings_light_horizontal(self: BoxFont, img: *pixman.Image) void {
    self.hline_middle(img, .light);
}

fn draw_box_drawings_heavy_horizontal(self: BoxFont, img: *pixman.Image) void {
    self.hline_middle(img, .heavy);
}

fn draw_box_drawings_light_vertical(self: BoxFont, img: *pixman.Image) void {
    self.vline_middle(img, .light);
}

fn draw_box_drawings_heavy_vertical(self: BoxFont, img: *pixman.Image) void {
    self.vline_middle(img, .heavy);
}

fn vline_middle(self: BoxFont, img: *pixman.Image, thickness: Thickness) void {
    const thick_px = thickness.height(self.thickness);
    self.vline(img, 0, self.height, (self.width - thick_px) / 2, thick_px);
}

fn hline_middle(self: BoxFont, img: *pixman.Image, thickness: Thickness) void {
    const thick_px = thickness.height(self.thickness);
    self.hline(img, 0, self.width, (self.height - thick_px) / 2, thick_px);
}

fn vline(
    self: BoxFont,
    img: *pixman.Image,
    y1: u32,
    y2: u32,
    x: u32,
    thickness_px: u32,
) void {
    const boxes = &[_]pixman.Box32{
        .{
            .x1 = @intCast(i32, @min(@max(x, 0), self.width)),
            .x2 = @intCast(i32, @min(@max(x + thickness_px, 0), self.width)),
            .y1 = @intCast(i32, @min(@max(y1, 0), self.height)),
            .y2 = @intCast(i32, @min(@max(y2, 0), self.height)),
        },
    };

    img.fillBoxes(.src, white, boxes) catch {};
}

fn hline(
    self: BoxFont,
    img: *pixman.Image,
    x1: u32,
    x2: u32,
    y: u32,
    thickness_px: u32,
) void {
    const boxes = &[_]pixman.Box32{
        .{
            .x1 = @intCast(i32, @min(@max(x1, 0), self.width)),
            .x2 = @intCast(i32, @min(@max(x2, 0), self.width)),
            .y1 = @intCast(i32, @min(@max(y, 0), self.height)),
            .y2 = @intCast(i32, @min(@max(y + thickness_px, 0), self.height)),
        },
    };

    img.fillBoxes(.src, white, boxes) catch {};
}

test "all" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var atlas_greyscale = try Atlas.init(alloc, 512, .greyscale);
    defer atlas_greyscale.deinit(alloc);

    const face: BoxFont = .{ .width = 18, .height = 36, .thickness = 2 };
    const glyph = try face.renderGlyph(
        alloc,
        &atlas_greyscale,
        0x2500,
    );
    try testing.expectEqual(@as(u32, face.width), glyph.width);
    try testing.expectEqual(@as(u32, face.height), glyph.height);
}
