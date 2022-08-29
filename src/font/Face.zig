//! Face represents a single font face. A single font face has a single set
//! of properties associated with it such as style, weight, etc.
//!
//! A Face isn't typically meant to be used directly. It is usually used
//! via a Family in order to store it in an Atlas.
const Face = @This();

const std = @import("std");
const builtin = @import("builtin");
const freetype = @import("freetype");
const assert = std.debug.assert;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Atlas = @import("../Atlas.zig");
const Glyph = @import("main.zig").Glyph;
const Library = @import("main.zig").Library;

const log = std.log.scoped(.font_face);

/// Our font face.
face: freetype.Face,

/// If a DPI can't be calculated, this DPI is used. This is probably
/// wrong on modern devices so it is highly recommended you get the DPI
/// using whatever platform method you can.
pub const default_dpi = if (builtin.os.tag == .macos) 72 else 96;

/// The desired size for loading a font.
pub const DesiredSize = struct {
    // Desired size in points
    points: u16,

    // The DPI of the screen so we can convert points to pixels.
    xdpi: u16 = default_dpi,
    ydpi: u16 = default_dpi,

    // Converts points to pixels
    pub fn pixels(self: DesiredSize) u16 {
        // 1 point = 1/72 inch
        return (self.points * self.ydpi) / 72;
    }
};

/// Initialize a new font face with the given source in-memory.
pub fn init(lib: Library, source: [:0]const u8, size: DesiredSize) !Face {
    const face = try lib.lib.initMemoryFace(source, 0);
    errdefer face.deinit();
    try face.selectCharmap(.unicode);
    try setSize_(face, size);

    return Face{ .face = face };
}

pub fn deinit(self: *Face) void {
    self.face.deinit();
    self.* = undefined;
}

/// Change the size of the loaded font face. If you're using a texture
/// atlas, you should invalidate all the previous values if cached.
pub fn setSize(self: Face, size: DesiredSize) !void {
    return try setSize_(self.face, size);
}

fn setSize_(face: freetype.Face, size: DesiredSize) !void {
    // If we have fixed sizes, we just have to try to pick the one closest
    // to what the user requested. Otherwise, we can choose an arbitrary
    // pixel size.
    if (!face.hasFixedSizes()) {
        const size_26dot6 = @intCast(i32, size.points << 6); // mult by 64
        try face.setCharSize(0, size_26dot6, size.xdpi, size.ydpi);
    } else try selectSizeNearest(face, size.pixels());
}

/// Selects the fixed size in the loaded face that is closest to the
/// requested pixel size.
fn selectSizeNearest(face: freetype.Face, size: u32) !void {
    var i: i32 = 0;
    var best_i: i32 = 0;
    var best_diff: i32 = 0;
    while (i < face.handle.*.num_fixed_sizes) : (i += 1) {
        const width = face.handle.*.available_sizes[@intCast(usize, i)].width;
        const diff = @intCast(i32, size) - @intCast(i32, width);
        if (i == 0 or diff < best_diff) {
            best_diff = diff;
            best_i = i;
        }
    }

    try face.selectSize(best_i);
}

/// Returns the glyph index for the given Unicode code point. If this
/// face doesn't support this glyph, null is returned.
pub fn glyphIndex(self: Face, cp: u32) ?u32 {
    return self.face.getCharIndex(cp);
}

/// Returns true if this font is colored. This can be used by callers to
/// determine what kind of atlas to pass in.
pub fn hasColor(self: Face) bool {
    return self.face.hasColor();
}

/// Load a glyph for this face. The codepoint can be either a u8 or
/// []const u8 depending on if you know it is ASCII or must be UTF-8 decoded.
pub fn loadGlyph(self: Face, alloc: Allocator, atlas: *Atlas, cp: u32) !Glyph {
    // We need a UTF32 codepoint for freetype
    const glyph_index = self.glyphIndex(cp) orelse return error.GlyphNotFound;
    return self.renderGlyph(alloc, atlas, glyph_index);
}

pub fn renderGlyph(self: Face, alloc: Allocator, atlas: *Atlas, glyph_index: u32) !Glyph {
    // If our glyph has color, we want to render the color
    try self.face.loadGlyph(glyph_index, .{
        .render = true,
        .color = self.face.hasColor(),
    });

    const glyph = self.face.handle.*.glyph;
    const bitmap = glyph.*.bitmap;

    // Ensure we know how to work with the font format. And assure that
    // or color depth is as expected on the texture atlas.
    const format: Atlas.Format = switch (bitmap.pixel_mode) {
        freetype.c.FT_PIXEL_MODE_GRAY => .greyscale,
        freetype.c.FT_PIXEL_MODE_BGRA => .rgba,
        else => {
            log.warn("pixel mode={}", .{bitmap.pixel_mode});
            @panic("unsupported pixel mode");
        },
    };
    assert(atlas.format == format);

    const src_w = bitmap.width;
    const src_h = bitmap.rows;
    const tgt_w = src_w;
    const tgt_h = src_h;

    const region = try atlas.reserve(alloc, tgt_w, tgt_h);

    // If we have data, copy it into the atlas
    if (region.width > 0 and region.height > 0) {
        const depth = @enumToInt(format);

        // We can avoid a buffer copy if our atlas width and bitmap
        // width match and the bitmap pitch is just the width (meaning
        // the data is tightly packed).
        const needs_copy = !(tgt_w == bitmap.width and (bitmap.width * depth) == bitmap.pitch);

        // If we need to copy the data, we copy it into a temporary buffer.
        const buffer = if (needs_copy) buffer: {
            var temp = try alloc.alloc(u8, tgt_w * tgt_h * depth);
            var dst_ptr = temp;
            var src_ptr = bitmap.buffer;
            var i: usize = 0;
            while (i < src_h) : (i += 1) {
                std.mem.copy(u8, dst_ptr, src_ptr[0 .. bitmap.width * depth]);
                dst_ptr = dst_ptr[tgt_w * depth ..];
                src_ptr += @intCast(usize, bitmap.pitch);
            }
            break :buffer temp;
        } else bitmap.buffer[0..(tgt_w * tgt_h * depth)];
        defer if (buffer.ptr != bitmap.buffer) alloc.free(buffer);

        // Write the glyph information into the atlas
        assert(region.width == tgt_w);
        assert(region.height == tgt_h);
        atlas.set(region, buffer);
    }

    // Store glyph metadata
    return Glyph{
        .width = tgt_w,
        .height = tgt_h,
        .offset_x = glyph.*.bitmap_left,
        .offset_y = glyph.*.bitmap_top,
        .atlas_x = region.x,
        .atlas_y = region.y,
        .advance_x = f26dot6ToFloat(glyph.*.advance.x),
    };
}

/// Convert 16.6 pixel format to pixels based on the scale factor of the
/// current font size.
pub fn unitsToPxY(self: Face, units: i32) i32 {
    return @intCast(i32, freetype.mulFix(
        units,
        @intCast(i32, self.face.handle.*.size.*.metrics.y_scale),
    ) >> 6);
}

/// Convert 26.6 pixel format to f32
fn f26dot6ToFloat(v: freetype.c.FT_F26Dot6) f32 {
    return @intToFloat(f32, v >> 6);
}

test {
    const testFont = @import("test.zig").fontRegular;
    const alloc = testing.allocator;

    var lib = try Library.init();
    defer lib.deinit();

    var atlas = try Atlas.init(alloc, 512, .greyscale);
    defer atlas.deinit(alloc);

    var font = try init(lib, testFont, .{ .points = 12 });
    defer font.deinit();

    // Generate all visible ASCII
    var i: u8 = 32;
    while (i < 127) : (i += 1) {
        _ = try font.loadGlyph(alloc, &atlas, i);
    }
}

test "color emoji" {
    const alloc = testing.allocator;
    const testFont = @import("test.zig").fontEmoji;

    var lib = try Library.init();
    defer lib.deinit();

    var atlas = try Atlas.init(alloc, 512, .rgba);
    defer atlas.deinit(alloc);

    var font = try init(lib, testFont, .{ .points = 12 });
    defer font.deinit();

    _ = try font.loadGlyph(alloc, &atlas, '🥸');
}
