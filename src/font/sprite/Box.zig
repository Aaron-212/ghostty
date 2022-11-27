//! This file contains functions for drawing the box drawing characters
//! (https://en.wikipedia.org/wiki/Box-drawing_character) and related
//! characters that are provided by the terminal.
//!
//! The box drawing logic is based off similar logic in Kitty and Foot.
//! The primary drawing code was ported directly and slightly modified from Foot
//! (https://codeberg.org/dnkl/foot/). Foot is licensed under the MIT
//! license and is copyright 2019 Daniel Eklöf.
//!
//! The modifications made are primarily around spacing, DPI calculations,
//! and adapting the code to our atlas model.
const Box = @This();

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const pixman = @import("pixman");
const font = @import("../main.zig");
const Atlas = @import("../../Atlas.zig");

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
            .heavy => base * 2,
        };
    }
};

pub fn renderGlyph(
    self: Box,
    alloc: Allocator,
    atlas: *Atlas,
    cp: u32,
) !font.Glyph {
    // Create the canvas we'll use to draw
    var canvas = try font.sprite.Canvas.init(alloc, self.width, self.height);
    defer canvas.deinit(alloc);

    // Perform the actual drawing
    try self.draw(alloc, canvas.image, cp);

    // Write the drawing to the atlas
    const region = try canvas.writeAtlas(alloc, atlas);

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

fn draw(self: Box, alloc: Allocator, img: *pixman.Image, cp: u32) !void {
    switch (cp) {
        0x2500 => self.draw_light_horizontal(img),
        0x2501 => self.draw_heavy_horizontal(img),
        0x2502 => self.draw_light_vertical(img),
        0x2503 => self.draw_heavy_vertical(img),
        0x2504 => self.draw_light_triple_dash_horizontal(img),
        0x2505 => self.draw_heavy_triple_dash_horizontal(img),
        0x2506 => self.draw_light_triple_dash_vertical(img),
        0x2507 => self.draw_heavy_triple_dash_vertical(img),
        0x2508 => self.draw_light_quadruple_dash_horizontal(img),
        0x2509 => self.draw_heavy_quadruple_dash_horizontal(img),
        0x250a => self.draw_light_quadruple_dash_vertical(img),
        0x250b => self.draw_heavy_quadruple_dash_vertical(img),
        0x250c => self.draw_light_down_and_right(img),
        0x250d => self.draw_down_light_and_right_heavy(img),
        0x250e => self.draw_down_heavy_and_right_light(img),
        0x250f => self.draw_heavy_down_and_right(img),

        0x2510 => self.draw_light_down_and_left(img),
        0x2511 => self.draw_down_light_and_left_heavy(img),
        0x2512 => self.draw_down_heavy_and_left_light(img),
        0x2513 => self.draw_heavy_down_and_left(img),
        0x2514 => self.draw_light_up_and_right(img),
        0x2515 => self.draw_up_light_and_right_heavy(img),
        0x2516 => self.draw_up_heavy_and_right_light(img),
        0x2517 => self.draw_heavy_up_and_right(img),
        0x2518 => self.draw_light_up_and_left(img),
        0x2519 => self.draw_up_light_and_left_heavy(img),
        0x251a => self.draw_up_heavy_and_left_light(img),
        0x251b => self.draw_heavy_up_and_left(img),
        0x251c => self.draw_light_vertical_and_right(img),
        0x251d => self.draw_vertical_light_and_right_heavy(img),
        0x251e => self.draw_up_heavy_and_right_down_light(img),
        0x251f => self.draw_down_heavy_and_right_up_light(img),

        0x2520 => self.draw_vertical_heavy_and_right_light(img),
        0x2521 => self.draw_down_light_and_right_up_heavy(img),
        0x2522 => self.draw_up_light_and_right_down_heavy(img),
        0x2523 => self.draw_heavy_vertical_and_right(img),
        0x2524 => self.draw_light_vertical_and_left(img),
        0x2525 => self.draw_vertical_light_and_left_heavy(img),
        0x2526 => self.draw_up_heavy_and_left_down_light(img),
        0x2527 => self.draw_down_heavy_and_left_up_light(img),
        0x2528 => self.draw_vertical_heavy_and_left_light(img),
        0x2529 => self.draw_down_light_and_left_up_heavy(img),
        0x252a => self.draw_up_light_and_left_down_heavy(img),
        0x252b => self.draw_heavy_vertical_and_left(img),
        0x252c => self.draw_light_down_and_horizontal(img),
        0x252d => self.draw_left_heavy_and_right_down_light(img),
        0x252e => self.draw_right_heavy_and_left_down_light(img),
        0x252f => self.draw_down_light_and_horizontal_heavy(img),

        0x2530 => self.draw_down_heavy_and_horizontal_light(img),
        0x2531 => self.draw_right_light_and_left_down_heavy(img),
        0x2532 => self.draw_left_light_and_right_down_heavy(img),
        0x2533 => self.draw_heavy_down_and_horizontal(img),
        0x2534 => self.draw_light_up_and_horizontal(img),
        0x2535 => self.draw_left_heavy_and_right_up_light(img),
        0x2536 => self.draw_right_heavy_and_left_up_light(img),
        0x2537 => self.draw_up_light_and_horizontal_heavy(img),
        0x2538 => self.draw_up_heavy_and_horizontal_light(img),
        0x2539 => self.draw_right_light_and_left_up_heavy(img),
        0x253a => self.draw_left_light_and_right_up_heavy(img),
        0x253b => self.draw_heavy_up_and_horizontal(img),
        0x253c => self.draw_light_vertical_and_horizontal(img),
        0x253d => self.draw_left_heavy_and_right_vertical_light(img),
        0x253e => self.draw_right_heavy_and_left_vertical_light(img),
        0x253f => self.draw_vertical_light_and_horizontal_heavy(img),

        0x2540 => self.draw_up_heavy_and_down_horizontal_light(img),
        0x2541 => self.draw_down_heavy_and_up_horizontal_light(img),
        0x2542 => self.draw_vertical_heavy_and_horizontal_light(img),
        0x2543 => self.draw_left_up_heavy_and_right_down_light(img),
        0x2544 => self.draw_right_up_heavy_and_left_down_light(img),
        0x2545 => self.draw_left_down_heavy_and_right_up_light(img),
        0x2546 => self.draw_right_down_heavy_and_left_up_light(img),
        0x2547 => self.draw_down_light_and_up_horizontal_heavy(img),
        0x2548 => self.draw_up_light_and_down_horizontal_heavy(img),
        0x2549 => self.draw_right_light_and_left_vertical_heavy(img),
        0x254a => self.draw_left_light_and_right_vertical_heavy(img),
        0x254b => self.draw_heavy_vertical_and_horizontal(img),
        0x254c => self.draw_light_double_dash_horizontal(img),
        0x254d => self.draw_heavy_double_dash_horizontal(img),
        0x254e => self.draw_light_double_dash_vertical(img),
        0x254f => self.draw_heavy_double_dash_vertical(img),

        0x2550 => self.draw_double_horizontal(img),
        0x2551 => self.draw_double_vertical(img),
        0x2552 => self.draw_down_single_and_right_double(img),
        0x2553 => self.draw_down_double_and_right_single(img),
        0x2554 => self.draw_double_down_and_right(img),
        0x2555 => self.draw_down_single_and_left_double(img),
        0x2556 => self.draw_down_double_and_left_single(img),
        0x2557 => self.draw_double_down_and_left(img),
        0x2558 => self.draw_up_single_and_right_double(img),
        0x2559 => self.draw_up_double_and_right_single(img),
        0x255a => self.draw_double_up_and_right(img),
        0x255b => self.draw_up_single_and_left_double(img),
        0x255c => self.draw_up_double_and_left_single(img),
        0x255d => self.draw_double_up_and_left(img),
        0x255e => self.draw_vertical_single_and_right_double(img),
        0x255f => self.draw_vertical_double_and_right_single(img),

        0x2560 => self.draw_double_vertical_and_right(img),
        0x2561 => self.draw_vertical_single_and_left_double(img),
        0x2562 => self.draw_vertical_double_and_left_single(img),
        0x2563 => self.draw_double_vertical_and_left(img),
        0x2564 => self.draw_down_single_and_horizontal_double(img),
        0x2565 => self.draw_down_double_and_horizontal_single(img),
        0x2566 => self.draw_double_down_and_horizontal(img),
        0x2567 => self.draw_up_single_and_horizontal_double(img),
        0x2568 => self.draw_up_double_and_horizontal_single(img),
        0x2569 => self.draw_double_up_and_horizontal(img),
        0x256a => self.draw_vertical_single_and_horizontal_double(img),
        0x256b => self.draw_vertical_double_and_horizontal_single(img),
        0x256c => self.draw_double_vertical_and_horizontal(img),
        0x256d...0x2570 => try self.draw_light_arc(alloc, img, cp),

        0x2571 => self.draw_light_diagonal_upper_right_to_lower_left(img),
        0x2572 => self.draw_light_diagonal_upper_left_to_lower_right(img),
        0x2573 => self.draw_light_diagonal_cross(img),
        0x2574 => self.draw_light_left(img),
        0x2575 => self.draw_light_up(img),
        0x2576 => self.draw_light_right(img),
        0x2577 => self.draw_light_down(img),
        0x2578 => self.draw_heavy_left(img),
        0x2579 => self.draw_heavy_up(img),
        0x257a => self.draw_heavy_right(img),
        0x257b => self.draw_heavy_down(img),
        0x257c => self.draw_light_left_and_heavy_right(img),
        0x257d => self.draw_light_up_and_heavy_down(img),
        0x257e => self.draw_heavy_left_and_light_right(img),
        0x257f => self.draw_heavy_up_and_light_down(img),

        0x2580 => self.draw_upper_half_block(img),
        0x2581 => self.draw_lower_one_eighth_block(img),
        0x2582 => self.draw_lower_one_quarter_block(img),
        0x2583 => self.draw_lower_three_eighths_block(img),
        0x2584 => self.draw_lower_half_block(img),
        0x2585 => self.draw_lower_five_eighths_block(img),
        0x2586 => self.draw_lower_three_quarters_block(img),
        0x2587 => self.draw_lower_seven_eighths_block(img),
        0x2588 => self.draw_full_block(img),
        0x2589 => self.draw_left_seven_eighths_block(img),
        0x258a => self.draw_left_three_quarters_block(img),
        0x258b => self.draw_left_five_eighths_block(img),
        0x258c => self.draw_left_half_block(img),
        0x258d => self.draw_left_three_eighths_block(img),
        0x258e => self.draw_left_one_quarter_block(img),
        0x258f => self.draw_left_one_eighth_block(img),

        0x2590 => self.draw_right_half_block(img),
        0x2591 => self.draw_light_shade(img),
        0x2592 => self.draw_medium_shade(img),
        0x2593 => self.draw_dark_shade(img),
        0x2594 => self.draw_upper_one_eighth_block(img),
        0x2595 => self.draw_right_one_eighth_block(img),
        0x2596...0x259f => self.draw_quadrant(img, cp),

        0x2800...0x28FF => self.draw_braille(img, cp),

        0x1FB00...0x1FB3B => self.draw_sextant(img, cp),

        0x1FB3C...0x1FB40,
        0x1FB47...0x1FB4B,
        0x1FB57...0x1FB5B,
        0x1FB62...0x1FB66,
        0x1FB6C...0x1FB6F,
        => try self.draw_wedge_triangle(img, cp),

        0x1FB41...0x1FB45,
        0x1FB4C...0x1FB50,
        0x1FB52...0x1FB56,
        0x1FB5D...0x1FB61,
        0x1FB68...0x1FB6B,
        => try self.draw_wedge_triangle_inverted(img, cp),

        0x1FB46,
        0x1FB51,
        0x1FB5C,
        0x1FB67,
        => try self.draw_wedge_triangle_and_box(img, cp),

        0x1FB9A => {
            try self.draw_wedge_triangle(img, 0x1fb6d);
            try self.draw_wedge_triangle(img, 0x1fb6f);
        },

        0x1FB9B => {
            try self.draw_wedge_triangle(img, 0x1fb6c);
            try self.draw_wedge_triangle(img, 0x1fb6e);
        },

        0x1FB70 => self.draw_vertical_one_eighth_block_n(img, 1),
        0x1FB71 => self.draw_vertical_one_eighth_block_n(img, 2),
        0x1FB72 => self.draw_vertical_one_eighth_block_n(img, 3),
        0x1FB73 => self.draw_vertical_one_eighth_block_n(img, 4),
        0x1FB74 => self.draw_vertical_one_eighth_block_n(img, 5),
        0x1FB75 => self.draw_vertical_one_eighth_block_n(img, 6),

        0x1FB76 => self.draw_horizontal_one_eighth_block_n(img, 1),
        0x1FB77 => self.draw_horizontal_one_eighth_block_n(img, 2),
        0x1FB78 => self.draw_horizontal_one_eighth_block_n(img, 3),
        0x1FB79 => self.draw_horizontal_one_eighth_block_n(img, 4),
        0x1FB7A => self.draw_horizontal_one_eighth_block_n(img, 5),
        0x1FB7B => self.draw_horizontal_one_eighth_block_n(img, 6),

        0x1fb82 => self.draw_upper_one_quarter_block(img),
        0x1fb83 => self.draw_upper_three_eighths_block(img),
        0x1fb84 => self.draw_upper_five_eighths_block(img),
        0x1fb85 => self.draw_upper_three_quarters_block(img),
        0x1fb86 => self.draw_upper_seven_eighths_block(img),

        0x1fb7c => self.draw_left_and_lower_one_eighth_block(img),
        0x1fb7d => self.draw_left_and_upper_one_eighth_block(img),
        0x1fb7e => self.draw_right_and_upper_one_eighth_block(img),
        0x1fb7f => self.draw_right_and_lower_one_eighth_block(img),
        0x1fb80 => self.draw_upper_and_lower_one_eighth_block(img),
        0x1fb81 => self.draw_horizontal_one_eighth_1358_block(img),

        0x1fb87 => self.draw_right_one_quarter_block(img),
        0x1fb88 => self.draw_right_three_eighths_block(img),
        0x1fb89 => self.draw_right_five_eighths_block(img),
        0x1fb8a => self.draw_right_three_quarters_block(img),
        0x1fb8b => self.draw_right_seven_eighths_block(img),

        else => return error.InvalidCodepoint,
    }
}

fn draw_light_horizontal(self: Box, img: *pixman.Image) void {
    self.hline_middle(img, .light);
}

fn draw_heavy_horizontal(self: Box, img: *pixman.Image) void {
    self.hline_middle(img, .heavy);
}

fn draw_light_vertical(self: Box, img: *pixman.Image) void {
    self.vline_middle(img, .light);
}

fn draw_heavy_vertical(self: Box, img: *pixman.Image) void {
    self.vline_middle(img, .heavy);
}

fn draw_light_triple_dash_horizontal(self: Box, img: *pixman.Image) void {
    self.draw_dash_horizontal(
        img,
        3,
        Thickness.light.height(self.thickness),
        @max(4, Thickness.light.height(self.thickness)),
    );
}

fn draw_heavy_triple_dash_horizontal(self: Box, img: *pixman.Image) void {
    self.draw_dash_horizontal(
        img,
        3,
        Thickness.heavy.height(self.thickness),
        @max(4, Thickness.light.height(self.thickness)),
    );
}

fn draw_light_triple_dash_vertical(self: Box, img: *pixman.Image) void {
    self.draw_dash_vertical(
        img,
        3,
        Thickness.light.height(self.thickness),
        @max(4, Thickness.light.height(self.thickness)),
    );
}

fn draw_heavy_triple_dash_vertical(self: Box, img: *pixman.Image) void {
    self.draw_dash_vertical(
        img,
        3,
        Thickness.heavy.height(self.thickness),
        @max(4, Thickness.light.height(self.thickness)),
    );
}

fn draw_light_quadruple_dash_horizontal(self: Box, img: *pixman.Image) void {
    self.draw_dash_horizontal(
        img,
        4,
        Thickness.light.height(self.thickness),
        @max(4, Thickness.light.height(self.thickness)),
    );
}

fn draw_heavy_quadruple_dash_horizontal(self: Box, img: *pixman.Image) void {
    self.draw_dash_horizontal(
        img,
        4,
        Thickness.heavy.height(self.thickness),
        @max(4, Thickness.light.height(self.thickness)),
    );
}

fn draw_light_quadruple_dash_vertical(self: Box, img: *pixman.Image) void {
    self.draw_dash_vertical(
        img,
        4,
        Thickness.light.height(self.thickness),
        @max(4, Thickness.light.height(self.thickness)),
    );
}

fn draw_heavy_quadruple_dash_vertical(self: Box, img: *pixman.Image) void {
    self.draw_dash_vertical(
        img,
        4,
        Thickness.heavy.height(self.thickness),
        @max(4, Thickness.light.height(self.thickness)),
    );
}

fn draw_light_down_and_right(self: Box, img: *pixman.Image) void {
    self.hline_middle_right(img, .light, .light);
    self.vline_middle_down(img, .light, .light);
}

fn draw_down_light_and_right_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle_right(img, .light, .heavy);
    self.vline_middle_down(img, .light, .light);
}

fn draw_down_heavy_and_right_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_right(img, .light, .light);
    self.vline_middle_down(img, .heavy, .light);
}

fn draw_heavy_down_and_right(self: Box, img: *pixman.Image) void {
    self.hline_middle_right(img, .heavy, .heavy);
    self.vline_middle_down(img, .heavy, .heavy);
}

fn draw_light_down_and_left(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .light);
    self.vline_middle_down(img, .light, .light);
}

fn draw_down_light_and_left_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .heavy);
    self.vline_middle_down(img, .light, .light);
}

fn draw_down_heavy_and_left_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .light);
    self.vline_middle_down(img, .heavy, .light);
}

fn draw_heavy_down_and_left(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .heavy, .heavy);
    self.vline_middle_down(img, .heavy, .heavy);
}

fn draw_light_up_and_right(self: Box, img: *pixman.Image) void {
    self.hline_middle_right(img, .light, .light);
    self.vline_middle_up(img, .light, .light);
}

fn draw_up_light_and_right_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle_right(img, .light, .heavy);
    self.vline_middle_up(img, .light, .light);
}

fn draw_up_heavy_and_right_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_right(img, .light, .light);
    self.vline_middle_up(img, .heavy, .light);
}

fn draw_heavy_up_and_right(self: Box, img: *pixman.Image) void {
    self.hline_middle_right(img, .heavy, .heavy);
    self.vline_middle_up(img, .heavy, .heavy);
}

fn draw_light_up_and_left(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .light);
    self.vline_middle_up(img, .light, .light);
}

fn draw_up_light_and_left_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .heavy);
    self.vline_middle_up(img, .light, .light);
}

fn draw_up_heavy_and_left_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .light);
    self.vline_middle_up(img, .heavy, .light);
}

fn draw_heavy_up_and_left(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .heavy, .heavy);
    self.vline_middle_up(img, .heavy, .heavy);
}

fn draw_light_vertical_and_right(self: Box, img: *pixman.Image) void {
    self.hline_middle_right(img, .light, .light);
    self.vline_middle(img, .light);
}

fn draw_vertical_light_and_right_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle_right(img, .light, .heavy);
    self.vline_middle(img, .light);
}

fn draw_up_heavy_and_right_down_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_right(img, .light, .light);
    self.vline_middle_up(img, .heavy, .light);
    self.vline_middle_down(img, .light, .light);
}

fn draw_down_heavy_and_right_up_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_right(img, .light, .light);
    self.vline_middle_up(img, .light, .light);
    self.vline_middle_down(img, .heavy, .light);
}

fn draw_vertical_heavy_and_right_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_right(img, .light, .light);
    self.vline_middle(img, .heavy);
}

fn draw_down_light_and_right_up_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle_right(img, .heavy, .heavy);
    self.vline_middle_up(img, .heavy, .heavy);
    self.vline_middle_down(img, .light, .light);
}

fn draw_up_light_and_right_down_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle_right(img, .heavy, .heavy);
    self.vline_middle_up(img, .light, .light);
    self.vline_middle_down(img, .heavy, .heavy);
}

fn draw_heavy_vertical_and_right(self: Box, img: *pixman.Image) void {
    self.hline_middle_right(img, .heavy, .heavy);
    self.vline_middle(img, .heavy);
}

fn draw_light_vertical_and_left(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .light);
    self.vline_middle(img, .light);
}

fn draw_vertical_light_and_left_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .heavy);
    self.vline_middle(img, .light);
}

fn draw_up_heavy_and_left_down_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .light);
    self.vline_middle_up(img, .heavy, .light);
    self.vline_middle_down(img, .light, .light);
}

fn draw_down_heavy_and_left_up_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .light);
    self.vline_middle_up(img, .light, .light);
    self.vline_middle_down(img, .heavy, .light);
}

fn draw_vertical_heavy_and_left_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .light);
    self.vline_middle(img, .heavy);
}

fn draw_down_light_and_left_up_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .heavy, .heavy);
    self.vline_middle_up(img, .heavy, .heavy);
    self.vline_middle_down(img, .light, .light);
}

fn draw_up_light_and_left_down_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .heavy, .heavy);
    self.vline_middle_up(img, .light, .light);
    self.vline_middle_down(img, .heavy, .heavy);
}

fn draw_heavy_vertical_and_left(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .heavy, .heavy);
    self.vline_middle(img, .heavy);
}

fn draw_light_down_and_horizontal(self: Box, img: *pixman.Image) void {
    self.hline_middle(img, .light);
    self.vline_middle_down(img, .light, .light);
}

fn draw_left_heavy_and_right_down_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .heavy);
    self.hline_middle_right(img, .light, .light);
    self.vline_middle_down(img, .light, .light);
}

fn draw_right_heavy_and_left_down_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .light);
    self.hline_middle_right(img, .light, .heavy);
    self.vline_middle_down(img, .light, .light);
}

fn draw_down_light_and_horizontal_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle(img, .heavy);
    self.vline_middle_down(img, .light, .light);
}

fn draw_down_heavy_and_horizontal_light(self: Box, img: *pixman.Image) void {
    self.hline_middle(img, .light);
    self.vline_middle_down(img, .heavy, .light);
}

fn draw_right_light_and_left_down_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .heavy, .heavy);
    self.hline_middle_right(img, .light, .light);
    self.vline_middle_down(img, .heavy, .heavy);
}

fn draw_left_light_and_right_down_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .light);
    self.hline_middle_right(img, .heavy, .heavy);
    self.vline_middle_down(img, .heavy, .heavy);
}

fn draw_heavy_down_and_horizontal(self: Box, img: *pixman.Image) void {
    self.hline_middle(img, .heavy);
    self.vline_middle_down(img, .heavy, .heavy);
}

fn draw_light_up_and_horizontal(self: Box, img: *pixman.Image) void {
    self.hline_middle(img, .light);
    self.vline_middle_up(img, .light, .light);
}

fn draw_left_heavy_and_right_up_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .heavy);
    self.hline_middle_right(img, .light, .light);
    self.vline_middle_up(img, .light, .light);
}

fn draw_right_heavy_and_left_up_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .light);
    self.hline_middle_right(img, .light, .heavy);
    self.vline_middle_up(img, .light, .light);
}

fn draw_up_light_and_horizontal_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle(img, .light);
    self.vline_middle_up(img, .light, .light);
}

fn draw_up_heavy_and_horizontal_light(self: Box, img: *pixman.Image) void {
    self.hline_middle(img, .light);
    self.vline_middle_up(img, .heavy, .light);
}

fn draw_right_light_and_left_up_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .heavy, .heavy);
    self.hline_middle_right(img, .light, .light);
    self.vline_middle_up(img, .heavy, .heavy);
}

fn draw_left_light_and_right_up_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .light);
    self.hline_middle_right(img, .heavy, .heavy);
    self.vline_middle_up(img, .heavy, .heavy);
}

fn draw_heavy_up_and_horizontal(self: Box, img: *pixman.Image) void {
    self.hline_middle(img, .heavy);
    self.vline_middle_up(img, .heavy, .heavy);
}

fn draw_light_vertical_and_horizontal(self: Box, img: *pixman.Image) void {
    self.hline_middle(img, .light);
    self.vline_middle(img, .light);
}

fn draw_left_heavy_and_right_vertical_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .heavy);
    self.hline_middle_right(img, .light, .light);
    self.vline_middle(img, .light);
}

fn draw_right_heavy_and_left_vertical_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .light);
    self.hline_middle_right(img, .light, .heavy);
    self.vline_middle(img, .light);
}

fn draw_vertical_light_and_horizontal_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle(img, .heavy);
    self.vline_middle(img, .light);
}

fn draw_up_heavy_and_down_horizontal_light(self: Box, img: *pixman.Image) void {
    self.hline_middle(img, .light);
    self.vline_middle_up(img, .heavy, .heavy);
    self.vline_middle_down(img, .light, .light);
}

fn draw_down_heavy_and_up_horizontal_light(self: Box, img: *pixman.Image) void {
    self.hline_middle(img, .light);
    self.vline_middle_up(img, .light, .light);
    self.vline_middle_down(img, .heavy, .light);
}

fn draw_vertical_heavy_and_horizontal_light(self: Box, img: *pixman.Image) void {
    self.hline_middle(img, .light);
    self.vline_middle(img, .heavy);
}

fn draw_left_up_heavy_and_right_down_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .heavy, .heavy);
    self.hline_middle_right(img, .light, .light);
    self.vline_middle_up(img, .heavy, .heavy);
    self.vline_middle_down(img, .light, .light);
}

fn draw_right_up_heavy_and_left_down_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .light);
    self.hline_middle_right(img, .heavy, .heavy);
    self.vline_middle_up(img, .heavy, .heavy);
    self.vline_middle_down(img, .light, .light);
}

fn draw_left_down_heavy_and_right_up_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .heavy, .heavy);
    self.hline_middle_right(img, .light, .light);
    self.vline_middle_up(img, .light, .light);
    self.vline_middle_down(img, .heavy, .heavy);
}

fn draw_right_down_heavy_and_left_up_light(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .light);
    self.hline_middle_right(img, .heavy, .heavy);
    self.vline_middle_up(img, .light, .light);
    self.vline_middle_down(img, .heavy, .heavy);
}

fn draw_down_light_and_up_horizontal_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle(img, .heavy);
    self.vline_middle_up(img, .heavy, .heavy);
    self.vline_middle_down(img, .light, .light);
}

fn draw_up_light_and_down_horizontal_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle(img, .heavy);
    self.vline_middle_up(img, .light, .light);
    self.vline_middle_down(img, .heavy, .heavy);
}

fn draw_right_light_and_left_vertical_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .heavy, .heavy);
    self.hline_middle_right(img, .light, .light);
    self.vline_middle(img, .heavy);
}

fn draw_left_light_and_right_vertical_heavy(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .light);
    self.hline_middle_right(img, .heavy, .heavy);
    self.vline_middle(img, .heavy);
}

fn draw_heavy_vertical_and_horizontal(self: Box, img: *pixman.Image) void {
    self.hline_middle(img, .heavy);
    self.vline_middle(img, .heavy);
}

fn draw_light_double_dash_horizontal(self: Box, img: *pixman.Image) void {
    self.draw_dash_horizontal(
        img,
        2,
        Thickness.light.height(self.thickness),
        Thickness.light.height(self.thickness),
    );
}

fn draw_heavy_double_dash_horizontal(self: Box, img: *pixman.Image) void {
    self.draw_dash_horizontal(
        img,
        2,
        Thickness.heavy.height(self.thickness),
        Thickness.heavy.height(self.thickness),
    );
}

fn draw_light_double_dash_vertical(self: Box, img: *pixman.Image) void {
    self.draw_dash_vertical(
        img,
        2,
        Thickness.light.height(self.thickness),
        Thickness.heavy.height(self.thickness),
    );
}

fn draw_heavy_double_dash_vertical(self: Box, img: *pixman.Image) void {
    self.draw_dash_vertical(
        img,
        2,
        Thickness.heavy.height(self.thickness),
        Thickness.heavy.height(self.thickness),
    );
}

fn draw_double_horizontal(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const mid = (self.height - thick_px * 3) / 2;
    self.hline(img, 0, self.width, mid, thick_px);
    self.hline(img, 0, self.width, mid + 2 * thick_px, thick_px);
}

fn draw_double_vertical(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const mid = (self.width - thick_px * 3) / 2;
    self.vline(img, 0, self.height, mid, thick_px);
    self.vline(img, 0, self.height, mid + 2 * thick_px, thick_px);
}

fn draw_down_single_and_right_double(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px * 3) / 2;
    const vmid = (self.width - thick_px) / 2;
    self.vline_middle_down(img, .light, .light);
    self.hline(img, vmid, self.width, hmid, thick_px);
    self.hline(img, vmid, self.width, hmid + 2 * thick_px, thick_px);
}

fn draw_down_double_and_right_single(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px) / 2;
    const vmid = (self.width - thick_px * 3) / 2;
    self.hline_middle_right(img, .light, .light);
    self.vline(img, hmid, self.height, vmid, thick_px);
    self.vline(img, hmid, self.height, vmid + 2 * thick_px, thick_px);
}

fn draw_double_down_and_right(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px * 3) / 2;
    const vmid = (self.width - thick_px * 3) / 2;
    self.vline(img, hmid, self.height, vmid, thick_px);
    self.vline(img, hmid + 2 * thick_px, self.height, vmid + 2 * thick_px, thick_px);
    self.hline(img, vmid, self.width, hmid, thick_px);
    self.hline(img, vmid + 2 * thick_px, self.width, hmid + 2 * thick_px, thick_px);
}

fn draw_down_single_and_left_double(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px * 3) / 2;
    const vmid = (self.width + thick_px) / 2;
    self.vline_middle_down(img, .light, .light);
    self.hline(img, 0, vmid, hmid, thick_px);
    self.hline(img, 0, vmid, hmid + 2 * thick_px, thick_px);
}

fn draw_down_double_and_left_single(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px) / 2;
    const vmid = (self.width - thick_px * 3) / 2;
    self.hline_middle_left(img, .light, .light);
    self.vline(img, hmid, self.height, vmid, thick_px);
    self.vline(img, hmid, self.height, vmid + 2 * thick_px, thick_px);
}

fn draw_double_down_and_left(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px * 3) / 2;
    const vmid = (self.width - thick_px * 3) / 2;
    self.vline(img, hmid + 2 * thick_px, self.height, vmid, thick_px);
    self.vline(img, hmid, self.height, vmid + 2 * thick_px, thick_px);
    self.hline(img, 0, vmid + 2 * thick_px, hmid, thick_px);
    self.hline(img, 0, vmid, hmid + 2 * thick_px, thick_px);
}

fn draw_up_single_and_right_double(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px * 3) / 2;
    const vmid = (self.width - thick_px) / 2;
    self.vline_middle_up(img, .light, .light);
    self.hline(img, vmid, self.width, hmid, thick_px);
    self.hline(img, vmid, self.width, hmid + 2 * thick_px, thick_px);
}

fn draw_up_double_and_right_single(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height + thick_px) / 2;
    const vmid = (self.width - thick_px * 3) / 2;
    self.hline_middle_right(img, .light, .light);
    self.vline(img, 0, hmid, vmid, thick_px);
    self.vline(img, 0, hmid, vmid + 2 * thick_px, thick_px);
}

fn draw_double_up_and_right(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px * 3) / 2;
    const vmid = (self.width - thick_px * 3) / 2;
    self.vline(img, 0, hmid + 2 * thick_px, vmid, thick_px);
    self.vline(img, 0, hmid, vmid + 2 * thick_px, thick_px);
    self.hline(img, vmid + 2 * thick_px, self.width, hmid, thick_px);
    self.hline(img, vmid, self.width, hmid + 2 * thick_px, thick_px);
}

fn draw_up_single_and_left_double(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px * 3) / 2;
    const vmid = (self.width + thick_px) / 2;
    self.vline_middle_up(img, .light, .light);
    self.hline(img, 0, vmid, hmid, thick_px);
    self.hline(img, 0, vmid, hmid + 2 * thick_px, thick_px);
}

fn draw_up_double_and_left_single(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height + thick_px) / 2;
    const vmid = (self.width - thick_px * 3) / 2;
    self.hline_middle_left(img, .light, .light);
    self.vline(img, 0, hmid, vmid, thick_px);
    self.vline(img, 0, hmid, vmid + 2 * thick_px, thick_px);
}

fn draw_double_up_and_left(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px * 3) / 2;
    const vmid = (self.width - thick_px * 3) / 2;
    self.vline(img, 0, hmid + 0 * thick_px + thick_px, vmid, thick_px);
    self.vline(img, 0, hmid + 2 * thick_px + thick_px, vmid + 2 * thick_px, thick_px);
    self.hline(img, 0, vmid, hmid, thick_px);
    self.hline(img, 0, vmid, hmid + 2 * thick_px, thick_px);
}

fn draw_vertical_single_and_right_double(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px * 3) / 2;
    const vmid = (self.width - thick_px) / 2;
    self.vline_middle(img, .light);
    self.hline(img, vmid, self.width, hmid, thick_px);
    self.hline(img, vmid, self.width, hmid + 2 * thick_px, thick_px);
}

fn draw_vertical_double_and_right_single(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const vmid = (self.width - thick_px * 3) / 2;
    self.hline(img, vmid + 2 * thick_px, self.width, (self.height - thick_px) / 2, thick_px);
    self.vline(img, 0, self.height, vmid, thick_px);
    self.vline(img, 0, self.height, vmid + 2 * thick_px, thick_px);
}

fn draw_double_vertical_and_right(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px * 3) / 2;
    const vmid = (self.width - thick_px * 3) / 2;
    self.vline(img, 0, self.height, vmid, thick_px);
    self.vline(img, 0, hmid, vmid + 2 * thick_px, thick_px);
    self.vline(img, hmid + 2 * thick_px, self.height, vmid + 2 * thick_px, thick_px);
    self.hline(img, vmid + 2 * thick_px, self.width, hmid, thick_px);
    self.hline(img, vmid + 2 * thick_px, self.width, hmid + 2 * thick_px, thick_px);
}

fn draw_vertical_single_and_left_double(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px * 3) / 2;
    const vmid = (self.width + thick_px) / 2;
    self.vline_middle(img, .light);
    self.hline(img, 0, vmid, hmid, thick_px);
    self.hline(img, 0, vmid, hmid + 2 * thick_px, thick_px);
}

fn draw_vertical_double_and_left_single(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const vmid = (self.width - thick_px * 3) / 2;
    self.hline(img, 0, vmid, (self.height - thick_px) / 2, thick_px);
    self.vline(img, 0, self.height, vmid, thick_px);
    self.vline(img, 0, self.height, vmid + 2 * thick_px, thick_px);
}

fn draw_double_vertical_and_left(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px * 3) / 2;
    const vmid = (self.width - thick_px * 3) / 2;
    self.vline(img, 0, self.height, vmid + 2 * thick_px, thick_px);
    self.vline(img, 0, hmid, vmid, thick_px);
    self.vline(img, hmid + 2 * thick_px, self.height, vmid, thick_px);
    self.hline(img, 0, vmid + thick_px, hmid, thick_px);
    self.hline(img, 0, vmid, hmid + 2 * thick_px, thick_px);
}

fn draw_down_single_and_horizontal_double(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px * 3) / 2;
    self.vline(img, hmid + 2 * thick_px, self.height, (self.width - thick_px) / 2, thick_px);
    self.hline(img, 0, self.width, hmid, thick_px);
    self.hline(img, 0, self.width, hmid + 2 * thick_px, thick_px);
}

fn draw_down_double_and_horizontal_single(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px) / 2;
    const vmid = (self.width - thick_px * 3) / 2;
    self.hline_middle(img, .light);
    self.vline(img, hmid, self.height, vmid, thick_px);
    self.vline(img, hmid, self.height, vmid + 2 * thick_px, thick_px);
}

fn draw_double_down_and_horizontal(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px * 3) / 2;
    const vmid = (self.width - thick_px * 3) / 2;
    self.hline(img, 0, self.width, hmid, thick_px);
    self.hline(img, 0, vmid, hmid + 2 * thick_px, thick_px);
    self.hline(img, vmid + 2 * thick_px, self.width, hmid + 2 * thick_px, thick_px);
    self.vline(img, hmid + 2 * thick_px, self.height, vmid, thick_px);
    self.vline(img, hmid + 2 * thick_px, self.height, vmid + 2 * thick_px, thick_px);
}

fn draw_up_single_and_horizontal_double(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px * 3) / 2;
    const vmid = (self.width - thick_px) / 2;
    self.vline(img, 0, hmid, vmid, thick_px);
    self.hline(img, 0, self.width, hmid, thick_px);
    self.hline(img, 0, self.width, hmid + 2 * thick_px, thick_px);
}

fn draw_up_double_and_horizontal_single(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px) / 2;
    const vmid = (self.width - thick_px * 3) / 2;
    self.hline_middle(img, .light);
    self.vline(img, 0, hmid, vmid, thick_px);
    self.vline(img, 0, hmid, vmid + 2 * thick_px, thick_px);
}

fn draw_double_up_and_horizontal(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px * 3) / 2;
    const vmid = (self.width - thick_px * 3) / 2;
    self.vline(img, 0, hmid, vmid, thick_px);
    self.vline(img, 0, hmid, vmid + 2 * thick_px, thick_px);
    self.hline(img, 0, vmid + thick_px, hmid, thick_px);
    self.hline(img, vmid + 2 * thick_px, self.width, hmid, thick_px);
    self.hline(img, 0, self.width, hmid + 2 * thick_px, thick_px);
}

fn draw_vertical_single_and_horizontal_double(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px * 3) / 2;
    self.vline_middle(img, .light);
    self.hline(img, 0, self.width, hmid, thick_px);
    self.hline(img, 0, self.width, hmid + 2 * thick_px, thick_px);
}

fn draw_vertical_double_and_horizontal_single(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const vmid = (self.width - thick_px * 3) / 2;
    self.hline_middle(img, .light);
    self.vline(img, 0, self.height, vmid, thick_px);
    self.vline(img, 0, self.height, vmid + 2 * thick_px, thick_px);
}

fn draw_double_vertical_and_horizontal(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    const hmid = (self.height - thick_px * 3) / 2;
    const vmid = (self.width - thick_px * 3) / 2;
    self.hline(img, 0, vmid, hmid, thick_px);
    self.hline(img, vmid + 2 * thick_px, self.width, hmid, thick_px);
    self.hline(img, 0, vmid, hmid + 2 * thick_px, thick_px);
    self.hline(img, vmid + 2 * thick_px, self.width, hmid + 2 * thick_px, thick_px);
    self.vline(img, 0, hmid + thick_px, vmid, thick_px);
    self.vline(img, 0, hmid, vmid + 2 * thick_px, thick_px);
    self.vline(img, hmid + 2 * thick_px, self.height, vmid, thick_px);
    self.vline(img, hmid + 2 * thick_px, self.height, vmid + 2 * thick_px, thick_px);
}

fn draw_light_diagonal_upper_right_to_lower_left(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    img.rasterizeTrapezoid(.{
        .top = pixman.Fixed.init(0),
        .bottom = pixman.Fixed.init(self.height),
        .left = .{
            .p1 = .{
                .x = pixman.Fixed.init(@intToFloat(f64, self.width) - @intToFloat(f64, thick_px) / 2),
                .y = pixman.Fixed.init(0),
            },

            .p2 = .{
                .x = pixman.Fixed.init(0 - @intToFloat(f64, thick_px) / 2),
                .y = pixman.Fixed.init(self.height),
            },
        },
        .right = .{
            .p1 = .{
                .x = pixman.Fixed.init(@intToFloat(f64, self.width) + @intToFloat(f64, thick_px) / 2),
                .y = pixman.Fixed.init(0),
            },

            .p2 = .{
                .x = pixman.Fixed.init(0 + @intToFloat(f64, thick_px) / 2),
                .y = pixman.Fixed.init(self.height),
            },
        },
    }, 0, 0);
}

fn draw_light_diagonal_upper_left_to_lower_right(self: Box, img: *pixman.Image) void {
    const thick_px = Thickness.light.height(self.thickness);
    img.rasterizeTrapezoid(.{
        .top = pixman.Fixed.init(0),
        .bottom = pixman.Fixed.init(self.height),
        .left = .{
            .p1 = .{
                .x = pixman.Fixed.init(0 - @intToFloat(f64, thick_px) / 2),
                .y = pixman.Fixed.init(0),
            },

            .p2 = .{
                .x = pixman.Fixed.init(@intToFloat(f64, self.width) - @intToFloat(f64, thick_px) / 2),
                .y = pixman.Fixed.init(self.height),
            },
        },
        .right = .{
            .p1 = .{
                .x = pixman.Fixed.init(0 + @intToFloat(f64, thick_px) / 2),
                .y = pixman.Fixed.init(0),
            },

            .p2 = .{
                .x = pixman.Fixed.init(@intToFloat(f64, self.width) + @intToFloat(f64, thick_px) / 2),
                .y = pixman.Fixed.init(self.height),
            },
        },
    }, 0, 0);
}

fn draw_light_diagonal_cross(self: Box, img: *pixman.Image) void {
    self.draw_light_diagonal_upper_right_to_lower_left(img);
    self.draw_light_diagonal_upper_left_to_lower_right(img);
}

fn draw_light_left(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .light);
}

fn draw_light_up(self: Box, img: *pixman.Image) void {
    self.vline_middle_up(img, .light, .light);
}

fn draw_light_right(self: Box, img: *pixman.Image) void {
    self.hline_middle_right(img, .light, .light);
}

fn draw_light_down(self: Box, img: *pixman.Image) void {
    self.vline_middle_down(img, .light, .light);
}

fn draw_heavy_left(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .heavy, .heavy);
}

fn draw_heavy_up(self: Box, img: *pixman.Image) void {
    self.vline_middle_up(img, .heavy, .heavy);
}

fn draw_heavy_right(self: Box, img: *pixman.Image) void {
    self.hline_middle_right(img, .heavy, .heavy);
}

fn draw_heavy_down(self: Box, img: *pixman.Image) void {
    self.vline_middle_down(img, .heavy, .heavy);
}

fn draw_light_left_and_heavy_right(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .light, .light);
    self.hline_middle_right(img, .heavy, .heavy);
}

fn draw_light_up_and_heavy_down(self: Box, img: *pixman.Image) void {
    self.vline_middle_up(img, .light, .light);
    self.vline_middle_down(img, .heavy, .heavy);
}

fn draw_heavy_left_and_light_right(self: Box, img: *pixman.Image) void {
    self.hline_middle_left(img, .heavy, .heavy);
    self.hline_middle_right(img, .light, .light);
}

fn draw_heavy_up_and_light_down(self: Box, img: *pixman.Image) void {
    self.vline_middle_up(img, .heavy, .heavy);
    self.vline_middle_down(img, .light, .light);
}

fn draw_upper_half_block(self: Box, img: *pixman.Image) void {
    self.rect(img, 0, 0, self.width, self.height / 2);
}

fn draw_lower_one_eighth_block(self: Box, img: *pixman.Image) void {
    self.rect(img, 0, self.height - (self.height / 8), self.width, self.height);
}

fn draw_lower_one_quarter_block(self: Box, img: *pixman.Image) void {
    self.rect(img, 0, self.height - (self.height / 4), self.width, self.height);
}

fn draw_lower_three_eighths_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        0,
        self.height - @floatToInt(u32, @round(3 * @intToFloat(f64, self.height) / 8)),
        self.width,
        self.height,
    );
}

fn draw_lower_half_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        0,
        self.height - @floatToInt(u32, @round(@intToFloat(f64, self.height) / 2)),
        self.width,
        self.height,
    );
}

fn draw_lower_five_eighths_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        0,
        self.height - @floatToInt(u32, @round(5 * @intToFloat(f64, self.height) / 8)),
        self.width,
        self.height,
    );
}

fn draw_lower_three_quarters_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        0,
        self.height - @floatToInt(u32, @round(3 * @intToFloat(f64, self.height) / 4)),
        self.width,
        self.height,
    );
}

fn draw_lower_seven_eighths_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        0,
        self.height - @floatToInt(u32, @round(7 * @intToFloat(f64, self.height) / 8)),
        self.width,
        self.height,
    );
}

fn draw_upper_one_quarter_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        0,
        0,
        self.width,
        @floatToInt(u32, @round(@intToFloat(f64, self.height) / 4)),
    );
}

fn draw_upper_three_eighths_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        0,
        0,
        self.width,
        @floatToInt(u32, @round(3 * @intToFloat(f64, self.height) / 8)),
    );
}

fn draw_upper_five_eighths_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        0,
        0,
        self.width,
        @floatToInt(u32, @round(5 * @intToFloat(f64, self.height) / 8)),
    );
}

fn draw_upper_three_quarters_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        0,
        0,
        self.width,
        @floatToInt(u32, @round(3 * @intToFloat(f64, self.height) / 4)),
    );
}

fn draw_upper_seven_eighths_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        0,
        0,
        self.width,
        @floatToInt(u32, @round(7 * @intToFloat(f64, self.height) / 8)),
    );
}

fn draw_full_block(self: Box, img: *pixman.Image) void {
    self.rect(img, 0, 0, self.width, self.height);
}

fn draw_left_seven_eighths_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        0,
        0,
        @floatToInt(u32, @round(7 * @intToFloat(f64, self.width) / 8)),
        self.height,
    );
}

fn draw_left_three_quarters_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        0,
        0,
        @floatToInt(u32, @round(3 * @intToFloat(f64, self.width) / 4)),
        self.height,
    );
}

fn draw_left_five_eighths_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        0,
        0,
        @floatToInt(u32, @round(5 * @intToFloat(f64, self.width) / 8)),
        self.height,
    );
}

fn draw_left_half_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        0,
        0,
        @floatToInt(u32, @round(@intToFloat(f64, self.width) / 2)),
        self.height,
    );
}

fn draw_left_three_eighths_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        0,
        0,
        @floatToInt(u32, @round(3 * @intToFloat(f64, self.width) / 8)),
        self.height,
    );
}

fn draw_left_one_quarter_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        0,
        0,
        @floatToInt(u32, @round(@intToFloat(f64, self.width) / 4)),
        self.height,
    );
}

fn draw_vertical_one_eighth_block_n(self: Box, img: *pixman.Image, n: u32) void {
    const x = @floatToInt(u32, @round(@intToFloat(f64, n) * @intToFloat(f64, self.width) / 8));
    const w = @floatToInt(u32, @round(@intToFloat(f64, self.width) / 8));
    self.rect(img, x, 0, x + w, self.height);
}

fn draw_left_one_eighth_block(self: Box, img: *pixman.Image) void {
    self.draw_vertical_one_eighth_block_n(img, 0);
}

fn draw_right_half_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        @floatToInt(u32, @round(@intToFloat(f64, self.width) / 2)),
        0,
        self.width,
        self.height,
    );
}

fn draw_pixman_shade(self: Box, img: *pixman.Image, v: u16) void {
    const boxes = &[_]pixman.Box32{
        .{
            .x1 = 0,
            .y1 = 0,
            .x2 = @intCast(i32, self.width),
            .y2 = @intCast(i32, self.height),
        },
    };

    img.fillBoxes(
        .src,
        .{ .red = 0, .green = 0, .blue = 0, .alpha = v },
        boxes,
    ) catch {};
}

fn draw_light_shade(self: Box, img: *pixman.Image) void {
    self.draw_pixman_shade(img, 0x4000);
}

fn draw_medium_shade(self: Box, img: *pixman.Image) void {
    self.draw_pixman_shade(img, 0x8000);
}

fn draw_dark_shade(self: Box, img: *pixman.Image) void {
    self.draw_pixman_shade(img, 0xc000);
}

fn draw_horizontal_one_eighth_block_n(self: Box, img: *pixman.Image, n: u32) void {
    const y = @floatToInt(u32, @round(@intToFloat(f64, n) * @intToFloat(f64, self.height) / 8));
    const h = @floatToInt(u32, @round(@intToFloat(f64, self.height) / 8));
    self.rect(img, 0, y, self.width, y + h);
}

fn draw_upper_one_eighth_block(self: Box, img: *pixman.Image) void {
    self.draw_horizontal_one_eighth_block_n(img, 0);
}

fn draw_right_one_eighth_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        self.width - @floatToInt(u32, @round(@intToFloat(f64, self.width) / 8)),
        0,
        self.width,
        self.height,
    );
}

fn draw_left_and_lower_one_eighth_block(self: Box, img: *pixman.Image) void {
    self.draw_left_one_eighth_block(img);
    self.draw_lower_one_eighth_block(img);
}

fn draw_left_and_upper_one_eighth_block(self: Box, img: *pixman.Image) void {
    self.draw_left_one_eighth_block(img);
    self.draw_upper_one_eighth_block(img);
}

fn draw_right_and_upper_one_eighth_block(self: Box, img: *pixman.Image) void {
    self.draw_right_one_eighth_block(img);
    self.draw_upper_one_eighth_block(img);
}

fn draw_right_and_lower_one_eighth_block(self: Box, img: *pixman.Image) void {
    self.draw_right_one_eighth_block(img);
    self.draw_lower_one_eighth_block(img);
}

fn draw_upper_and_lower_one_eighth_block(self: Box, img: *pixman.Image) void {
    self.draw_upper_one_eighth_block(img);
    self.draw_lower_one_eighth_block(img);
}

fn draw_horizontal_one_eighth_1358_block(self: Box, img: *pixman.Image) void {
    self.draw_upper_one_eighth_block(img);
    self.draw_horizontal_one_eighth_block_n(img, 2);
    self.draw_horizontal_one_eighth_block_n(img, 4);
    self.draw_lower_one_eighth_block(img);
}

fn draw_right_one_quarter_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        self.width - @floatToInt(u32, @round(@intToFloat(f64, self.width) / 4)),
        0,
        self.width,
        self.height,
    );
}

fn draw_right_three_quarters_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        self.width - @floatToInt(u32, @round(3 * @intToFloat(f64, self.width) / 4)),
        0,
        self.width,
        self.height,
    );
}

fn draw_right_three_eighths_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        self.width - @floatToInt(u32, @round(3 * @intToFloat(f64, self.width) / 8)),
        0,
        self.width,
        self.height,
    );
}

fn draw_right_five_eighths_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        self.width - @floatToInt(u32, @round(5 * @intToFloat(f64, self.width) / 8)),
        0,
        self.width,
        self.height,
    );
}

fn draw_right_seven_eighths_block(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        self.width - @floatToInt(u32, @round(7 * @intToFloat(f64, self.width) / 8)),
        0,
        self.width,
        self.height,
    );
}

fn quad_upper_left(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        0,
        0,
        @floatToInt(u32, @ceil(@intToFloat(f64, self.width) / 2)),
        @floatToInt(u32, @ceil(@intToFloat(f64, self.height) / 2)),
    );
}

fn quad_upper_right(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        @floatToInt(u32, @floor(@intToFloat(f64, self.width) / 2)),
        0,
        self.width,
        @floatToInt(u32, @ceil(@intToFloat(f64, self.height) / 2)),
    );
}

fn quad_lower_left(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        0,
        @floatToInt(u32, @floor(@intToFloat(f64, self.height) / 2)),
        @floatToInt(u32, @ceil(@intToFloat(f64, self.width) / 2)),
        self.height,
    );
}

fn quad_lower_right(self: Box, img: *pixman.Image) void {
    self.rect(
        img,
        @floatToInt(u32, @floor(@intToFloat(f64, self.width) / 2)),
        @floatToInt(u32, @floor(@intToFloat(f64, self.height) / 2)),
        self.width,
        self.height,
    );
}

fn draw_quadrant(self: Box, img: *pixman.Image, cp: u32) void {
    const UPPER_LEFT: u8 = 1 << 0;
    const UPPER_RIGHT: u8 = 1 << 1;
    const LOWER_LEFT: u8 = 1 << 2;
    const LOWER_RIGHT: u8 = 1 << 3;
    const matrix: [10]u8 = .{
        LOWER_LEFT,
        LOWER_RIGHT,
        UPPER_LEFT,
        UPPER_LEFT | LOWER_LEFT | LOWER_RIGHT,
        UPPER_LEFT | LOWER_RIGHT,
        UPPER_LEFT | UPPER_RIGHT | LOWER_LEFT,
        UPPER_LEFT | UPPER_RIGHT | LOWER_RIGHT,
        UPPER_RIGHT,
        UPPER_RIGHT | LOWER_LEFT,
        UPPER_RIGHT | LOWER_LEFT | LOWER_RIGHT,
    };

    assert(cp >= 0x2596 and cp <= 0x259f);
    const idx = cp - 0x2596;
    const encoded = matrix[idx];

    if (encoded & UPPER_LEFT == UPPER_LEFT) self.quad_upper_left(img);
    if (encoded & UPPER_RIGHT == UPPER_RIGHT) self.quad_upper_right(img);
    if (encoded & LOWER_LEFT == LOWER_LEFT) self.quad_lower_left(img);
    if (encoded & LOWER_RIGHT == LOWER_RIGHT) self.quad_lower_right(img);
}

fn draw_braille(self: Box, img: *pixman.Image, cp: u32) void {
    var w: u32 = @min(self.width / 4, self.height / 8);
    var x_spacing: u32 = self.width / 4;
    var y_spacing: u32 = self.height / 8;
    var x_margin: u32 = x_spacing / 2;
    var y_margin: u32 = y_spacing / 2;

    var x_px_left: u32 = self.width - 2 * x_margin - x_spacing - 2 * w;
    var y_px_left: u32 = self.height - 2 * y_margin - 3 * y_spacing - 4 * w;

    // First, try hard to ensure the DOT width is non-zero
    if (x_px_left >= 2 and y_px_left >= 4 and w == 0) {
        w += 1;
        x_px_left -= 2;
        y_px_left -= 4;
    }

    // Second, prefer a non-zero margin
    if (x_px_left >= 2 and x_margin == 0) {
        x_margin = 1;
        x_px_left -= 2;
    }
    if (y_px_left >= 2 and y_margin == 0) {
        y_margin = 1;
        y_px_left -= 2;
    }

    // Third, increase spacing
    if (x_px_left >= 1) {
        x_spacing += 1;
        x_px_left -= 1;
    }
    if (y_px_left >= 3) {
        y_spacing += 1;
        y_px_left -= 3;
    }

    // Fourth, margins (“spacing”, but on the sides)
    if (x_px_left >= 2) {
        x_margin += 1;
        x_px_left -= 2;
    }
    if (y_px_left >= 2) {
        y_margin += 1;
        y_px_left -= 2;
    }

    // Last - increase dot width
    if (x_px_left >= 2 and y_px_left >= 4) {
        w += 1;
        x_px_left -= 2;
        y_px_left -= 4;
    }

    assert(x_px_left <= 1 or y_px_left <= 1);
    assert(2 * x_margin + 2 * w + x_spacing <= self.width);
    assert(2 * y_margin + 4 * w + 3 * y_spacing <= self.height);

    const x = [2]u32{ x_margin, x_margin + w + x_spacing };
    const y = y: {
        var y: [4]u32 = undefined;
        y[0] = y_margin;
        y[1] = y[0] + w + y_spacing;
        y[2] = y[1] + w + y_spacing;
        y[3] = y[2] + w + y_spacing;
        break :y y;
    };

    assert(cp >= 0x2800);
    assert(cp <= 0x28ff);
    const sym = cp - 0x2800;

    // Left side
    if (sym & 1 > 0)
        self.rect(img, x[0], y[0], x[0] + w, y[0] + w);
    if (sym & 2 > 0)
        self.rect(img, x[0], y[1], x[0] + w, y[1] + w);
    if (sym & 4 > 0)
        self.rect(img, x[0], y[2], x[0] + w, y[2] + w);

    // Right side
    if (sym & 8 > 0)
        self.rect(img, x[1], y[0], x[1] + w, y[0] + w);
    if (sym & 16 > 0)
        self.rect(img, x[1], y[1], x[1] + w, y[1] + w);
    if (sym & 32 > 0)
        self.rect(img, x[1], y[2], x[1] + w, y[2] + w);

    // 8-dot patterns
    if (sym & 64 > 0)
        self.rect(img, x[0], y[3], x[0] + w, y[3] + w);
    if (sym & 128 > 0)
        self.rect(img, x[1], y[3], x[1] + w, y[3] + w);
}

fn draw_sextant(self: Box, img: *pixman.Image, cp: u32) void {
    const UPPER_LEFT: u8 = 1 << 0;
    const MIDDLE_LEFT: u8 = 1 << 1;
    const LOWER_LEFT: u8 = 1 << 2;
    const UPPER_RIGHT: u8 = 1 << 3;
    const MIDDLE_RIGHT: u8 = 1 << 4;
    const LOWER_RIGHT: u8 = 1 << 5;

    const matrix: [60]u8 = .{
        // U+1fb00 - U+1fb0f
        UPPER_LEFT,
        UPPER_RIGHT,
        UPPER_LEFT | UPPER_RIGHT,
        MIDDLE_LEFT,
        UPPER_LEFT | MIDDLE_LEFT,
        UPPER_RIGHT | MIDDLE_LEFT,
        UPPER_LEFT | UPPER_RIGHT | MIDDLE_LEFT,
        MIDDLE_RIGHT,
        UPPER_LEFT | MIDDLE_RIGHT,
        UPPER_RIGHT | MIDDLE_RIGHT,
        UPPER_LEFT | UPPER_RIGHT | MIDDLE_RIGHT,
        MIDDLE_LEFT | MIDDLE_RIGHT,
        UPPER_LEFT | MIDDLE_LEFT | MIDDLE_RIGHT,
        UPPER_RIGHT | MIDDLE_LEFT | MIDDLE_RIGHT,
        UPPER_LEFT | UPPER_RIGHT | MIDDLE_LEFT | MIDDLE_RIGHT,
        LOWER_LEFT,

        // U+1fb10 - U+1fb1f
        UPPER_LEFT | LOWER_LEFT,
        UPPER_RIGHT | LOWER_LEFT,
        UPPER_LEFT | UPPER_RIGHT | LOWER_LEFT,
        MIDDLE_LEFT | LOWER_LEFT,
        UPPER_RIGHT | MIDDLE_LEFT | LOWER_LEFT,
        UPPER_LEFT | UPPER_RIGHT | MIDDLE_LEFT | LOWER_LEFT,
        MIDDLE_RIGHT | LOWER_LEFT,
        UPPER_LEFT | MIDDLE_RIGHT | LOWER_LEFT,
        UPPER_RIGHT | MIDDLE_RIGHT | LOWER_LEFT,
        UPPER_LEFT | UPPER_RIGHT | MIDDLE_RIGHT | LOWER_LEFT,
        MIDDLE_LEFT | MIDDLE_RIGHT | LOWER_LEFT,
        UPPER_LEFT | MIDDLE_LEFT | MIDDLE_RIGHT | LOWER_LEFT,
        UPPER_RIGHT | MIDDLE_LEFT | MIDDLE_RIGHT | LOWER_LEFT,
        UPPER_LEFT | UPPER_RIGHT | MIDDLE_LEFT | MIDDLE_RIGHT | LOWER_LEFT,
        LOWER_RIGHT,
        UPPER_LEFT | LOWER_RIGHT,

        // U+1fb20 - U+1fb2f
        UPPER_RIGHT | LOWER_RIGHT,
        UPPER_LEFT | UPPER_RIGHT | LOWER_RIGHT,
        MIDDLE_LEFT | LOWER_RIGHT,
        UPPER_LEFT | MIDDLE_LEFT | LOWER_RIGHT,
        UPPER_RIGHT | MIDDLE_LEFT | LOWER_RIGHT,
        UPPER_LEFT | UPPER_RIGHT | MIDDLE_LEFT | LOWER_RIGHT,
        MIDDLE_RIGHT | LOWER_RIGHT,
        UPPER_LEFT | MIDDLE_RIGHT | LOWER_RIGHT,
        UPPER_LEFT | UPPER_RIGHT | MIDDLE_RIGHT | LOWER_RIGHT,
        MIDDLE_LEFT | MIDDLE_RIGHT | LOWER_RIGHT,
        UPPER_LEFT | MIDDLE_LEFT | MIDDLE_RIGHT | LOWER_RIGHT,
        UPPER_RIGHT | MIDDLE_LEFT | MIDDLE_RIGHT | LOWER_RIGHT,
        UPPER_LEFT | UPPER_RIGHT | MIDDLE_LEFT | MIDDLE_RIGHT | LOWER_RIGHT,
        LOWER_LEFT | LOWER_RIGHT,
        UPPER_LEFT | LOWER_LEFT | LOWER_RIGHT,
        UPPER_RIGHT | LOWER_LEFT | LOWER_RIGHT,

        // U+1fb30 - U+1fb3b
        UPPER_LEFT | UPPER_RIGHT | LOWER_LEFT | LOWER_RIGHT,
        MIDDLE_LEFT | LOWER_LEFT | LOWER_RIGHT,
        UPPER_LEFT | MIDDLE_LEFT | LOWER_LEFT | LOWER_RIGHT,
        UPPER_RIGHT | MIDDLE_LEFT | LOWER_LEFT | LOWER_RIGHT,
        UPPER_LEFT | UPPER_RIGHT | MIDDLE_LEFT | LOWER_LEFT | LOWER_RIGHT,
        MIDDLE_RIGHT | LOWER_LEFT | LOWER_RIGHT,
        UPPER_LEFT | MIDDLE_RIGHT | LOWER_LEFT | LOWER_RIGHT,
        UPPER_RIGHT | MIDDLE_RIGHT | LOWER_LEFT | LOWER_RIGHT,
        UPPER_LEFT | UPPER_RIGHT | MIDDLE_RIGHT | LOWER_LEFT | LOWER_RIGHT,
        MIDDLE_LEFT | MIDDLE_RIGHT | LOWER_LEFT | LOWER_RIGHT,
        UPPER_LEFT | MIDDLE_LEFT | MIDDLE_RIGHT | LOWER_LEFT | LOWER_RIGHT,
        UPPER_RIGHT | MIDDLE_LEFT | MIDDLE_RIGHT | LOWER_LEFT | LOWER_RIGHT,
    };

    assert(cp >= 0x1fb00 and cp <= 0x1fb3b);
    const idx = cp - 0x1fb00;
    const encoded = matrix[idx];

    const x_halfs = self.xHalfs();
    const y_thirds = self.yThirds();

    if (encoded & UPPER_LEFT > 0) self.rect(img, 0, 0, x_halfs[0], y_thirds[0]);
    if (encoded & MIDDLE_LEFT > 0) self.rect(img, 0, y_thirds[0], x_halfs[0], y_thirds[1]);
    if (encoded & LOWER_LEFT > 0) self.rect(img, 0, y_thirds[1], x_halfs[0], self.height);
    if (encoded & UPPER_RIGHT > 0) self.rect(img, x_halfs[1], 0, self.width, y_thirds[0]);
    if (encoded & MIDDLE_RIGHT > 0) self.rect(img, x_halfs[1], y_thirds[0], self.width, y_thirds[1]);
    if (encoded & LOWER_RIGHT > 0) self.rect(img, x_halfs[1], y_thirds[1], self.width, self.height);
}

fn xHalfs(self: Box) [2]u32 {
    return .{
        @floatToInt(u32, @round(@intToFloat(f64, self.width) / 2)),
        @floatToInt(u32, @intToFloat(f64, self.width) / 2),
    };
}

fn yThirds(self: Box) [2]u32 {
    return switch (@mod(self.height, 3)) {
        0 => .{ self.height / 3, 2 * self.height / 3 },
        1 => .{ self.height / 3, 2 * self.height / 3 + 1 },
        2 => .{ self.height / 3 + 1, 2 * self.height / 3 },
        else => unreachable,
    };
}

fn draw_wedge_triangle(self: Box, img: *pixman.Image, cp: u32) !void {
    const width = self.width;
    const height = self.height;

    const x_halfs = self.xHalfs();
    const y_thirds = self.yThirds();
    const halfs0 = x_halfs[0];
    const halfs1 = x_halfs[1];
    const thirds0 = y_thirds[0];
    const thirds1 = y_thirds[1];

    var p1_x: u32 = 0;
    var p2_x: u32 = 0;
    var p3_x: u32 = 0;
    var p1_y: u32 = 0;
    var p2_y: u32 = 0;
    var p3_y: u32 = 0;

    switch (cp) {
        0x1fb3c => {
            p3_x = halfs0;
            p1_y = thirds1;
            p2_y = height;
            p3_y = height;
        },

        0x1fb52 => {
            p3_x = halfs0;
            p1_y = thirds1;
            p2_y = height;
            p3_y = height;
        },

        0x1fb3d => {
            p3_x = width;
            p1_y = thirds1;
            p2_y = height;
            p3_y = height;
        },

        0x1fb53 => {
            p3_x = width;
            p1_y = thirds1;
            p2_y = height;
            p3_y = height;
        },

        0x1fb3e => {
            p3_x = halfs0;
            p1_y = thirds0;
            p2_y = height;
            p3_y = height;
        },

        0x1fb54 => {
            p3_x = halfs0;
            p1_y = thirds0;
            p2_y = height;
            p3_y = height;
        },

        0x1fb3f => {
            p3_x = width;
            p1_y = thirds0;
            p2_y = height;
            p3_y = height;
        },

        0x1fb55 => {
            p3_x = width;
            p1_y = thirds0;
            p2_y = height;
            p3_y = height;
        },

        0x1fb40, 0x1fb56 => {
            p3_x = halfs0;
            p1_y = 0;
            p2_y = height;
            p3_y = height;
        },

        0x1fb47 => {
            p1_x = width;
            p2_x = width;
            p3_x = halfs1;
            p1_y = thirds1;
            p2_y = height;
            p3_y = height;
        },

        0x1fb5d => {
            p1_x = width;
            p2_x = width;
            p3_x = halfs1;
            p1_y = thirds1;
            p2_y = height;
            p3_y = height;
        },

        0x1fb48 => {
            p1_x = width;
            p2_x = width;
            p3_x = 0;
            p1_y = thirds1;
            p2_y = height;
            p3_y = height;
        },

        0x1fb5e => {
            p1_x = width;
            p2_x = width;
            p3_x = 0;
            p1_y = thirds1;
            p2_y = height;
            p3_y = height;
        },

        0x1fb49 => {
            p1_x = width;
            p2_x = width;
            p3_x = halfs1;
            p1_y = thirds0;
            p2_y = height;
            p3_y = height;
        },

        0x1fb5f => {
            p1_x = width;
            p2_x = width;
            p3_x = halfs1;
            p1_y = thirds0;
            p2_y = height;
            p3_y = height;
        },

        0x1fb4a => {
            p1_x = width;
            p2_x = width;
            p3_x = 0;
            p1_y = thirds0;
            p2_y = height;
            p3_y = height;
        },

        0x1fb60 => {
            p1_x = width;
            p2_x = width;
            p3_x = 0;
            p1_y = thirds0;
            p2_y = height;
            p3_y = height;
        },

        0x1fb4b, 0x1fb61 => {
            p1_x = width;
            p2_x = width;
            p3_x = halfs1;
            p1_y = 0;
            p2_y = height;
            p3_y = height;
        },

        0x1fb57 => {
            p3_x = halfs0;
            p2_y = thirds0;
        },

        0x1fb41 => {
            p3_x = halfs0;
            p2_y = thirds0;
        },

        0x1fb58 => {
            p3_x = width;
            p2_y = thirds0;
        },

        0x1fb42 => {
            p3_x = width;
            p2_y = thirds0;
        },

        0x1fb59 => {
            p3_x = halfs0;
            p2_y = thirds1;
        },

        0x1fb43 => {
            p3_x = halfs0;
            p2_y = thirds1;
        },

        0x1fb5a => {
            p3_x = width;
            p2_y = thirds1;
        },

        0x1fb44 => {
            p3_x = width;
            p2_y = thirds1;
        },

        0x1fb5b, 0x1fb45 => {
            p3_x = halfs0;
            p2_y = height;
        },

        0x1fb62 => {
            p1_x = width;
            p2_x = width;
            p3_x = halfs1;
            p2_y = thirds0;
        },

        0x1fb4c => {
            p1_x = width;
            p2_x = width;
            p3_x = halfs1;
            p2_y = thirds0;
        },

        0x1fb63 => {
            p1_x = width;
            p2_x = width;
            p3_x = 0;
            p2_y = thirds0;
        },

        0x1fb4d => {
            p1_x = width;
            p2_x = width;
            p3_x = 0;
            p2_y = thirds0;
        },

        0x1fb64 => {
            p1_x = width;
            p2_x = width;
            p3_x = halfs1;
            p2_y = thirds1;
        },

        0x1fb4e => {
            p1_x = width;
            p2_x = width;
            p3_x = halfs1;
            p2_y = thirds1;
        },

        0x1fb65 => {
            p1_x = width;
            p2_x = width;
            p3_x = 0;
            p2_y = thirds1;
        },

        0x1fb4f => {
            p1_x = width;
            p2_x = width;
            p3_x = 0;
            p2_y = thirds1;
        },

        0x1fb66, 0x1fb50 => {
            p1_x = width;
            p2_x = width;
            p3_x = halfs1;
            p2_y = height;
        },

        0x1fb46 => {
            p1_x = 0;
            p1_y = thirds1;
            p2_x = width;
            p2_y = thirds0;
            p3_x = width;
            p3_y = p1_y;
        },

        0x1fb51 => {
            p1_x = 0;
            p1_y = thirds0;
            p2_x = 0;
            p2_y = thirds1;
            p3_x = width;
            p3_y = p2_y;
        },

        0x1fb5c => {
            p1_x = 0;
            p1_y = thirds0;
            p2_x = 0;
            p2_y = thirds1;
            p3_x = width;
            p3_y = p1_y;
        },

        0x1fb67 => {
            p1_x = 0;
            p1_y = thirds0;
            p2_x = width;
            p2_y = p1_y;
            p3_x = width;
            p3_y = thirds1;
        },

        0x1fb6c, 0x1fb68 => {
            p1_x = 0;
            p1_y = 0;
            p2_x = halfs0;
            p2_y = height / 2;
            p3_x = 0;
            p3_y = height;
        },

        0x1fb6d, 0x1fb69 => {
            p1_x = 0;
            p1_y = 0;
            p2_x = halfs1;
            p2_y = height / 2;
            p3_x = width;
            p3_y = 0;
        },

        0x1fb6e, 0x1fb6a => {
            p1_x = width;
            p1_y = 0;
            p2_x = halfs1;
            p2_y = height / 2;
            p3_x = width;
            p3_y = height;
        },

        0x1fb6f, 0x1fb6b => {
            p1_x = 0;
            p1_y = height;
            p2_x = halfs1;
            p2_y = height / 2;
            p3_x = width;
            p3_y = height;
        },

        else => unreachable,
    }

    const tris = &[_]pixman.Triangle{
        .{
            .p1 = .{ .x = pixman.Fixed.init(p1_x), .y = pixman.Fixed.init(p1_y) },
            .p2 = .{ .x = pixman.Fixed.init(p2_x), .y = pixman.Fixed.init(p2_y) },
            .p3 = .{ .x = pixman.Fixed.init(p3_x), .y = pixman.Fixed.init(p3_y) },
        },
    };

    const src = try pixman.Image.createSolidFill(white);
    defer _ = src.unref();
    img.compositeTriangles(.over, src, .a8, 0, 0, 0, 0, tris);
}

fn draw_wedge_triangle_inverted(self: Box, img: *pixman.Image, cp: u32) !void {
    try self.draw_wedge_triangle(img, cp);

    const src = try pixman.Image.createSolidFill(white);
    defer _ = src.unref();
    img.composite(
        .out,
        src,
        null,
        0,
        0,
        0,
        0,
        0,
        0,
        @intCast(u16, self.width),
        @intCast(u16, self.height),
    );
}

fn draw_wedge_triangle_and_box(self: Box, img: *pixman.Image, cp: u32) !void {
    try self.draw_wedge_triangle(img, cp);

    const y_thirds = self.yThirds();
    const box: pixman.Box32 = switch (cp) {
        0x1fb46, 0x1fb51 => .{
            .x1 = 0,
            .y1 = @intCast(i32, y_thirds[1]),
            .x2 = @intCast(i32, self.width),
            .y2 = @intCast(i32, self.height),
        },

        0x1fb5c, 0x1fb67 => .{
            .x1 = 0,
            .y1 = 0,
            .x2 = @intCast(i32, self.width),
            .y2 = @intCast(i32, y_thirds[0]),
        },

        else => unreachable,
    };

    const boxes = &[_]pixman.Box32{box};
    img.fillBoxes(.src, white, boxes) catch {};
}

fn draw_light_arc(
    self: Box,
    alloc: Allocator,
    img: *pixman.Image,
    cp: u32,
) !void {
    const supersample = 4;
    const height = self.height * supersample;
    const width = self.width * supersample;
    const stride = pixman.FormatCode.a8.strideForWidth(width);

    // Allocate our buffer
    var data = try alloc.alloc(u8, height * @intCast(u32, stride));
    defer alloc.free(data);
    std.mem.set(u8, data, 0);

    const height_pixels = self.height;
    const width_pixels = self.width;
    const thick_pixels = Thickness.light.height(self.thickness);
    const thick = thick_pixels * supersample;

    const circle_inner_edge = (@min(width_pixels, height_pixels) - thick_pixels) / 2;

    // We want to draw the quartercircle by filling small circles (with r =
    // thickness/2.) whose centers are on its edge. This means to get the
    // radius of the quartercircle, we add the exact half thickness to the
    // radius of the inner circle.
    var c_r: f64 = @intToFloat(f64, circle_inner_edge) + @intToFloat(f64, thick_pixels) / 2;

    // We need to draw short lines from the end of the quartercircle to the
    // box-edges, store one endpoint (the other is the edge of the
    // quartercircle) in these vars.
    var vert_to: u32 = 0;
    var hor_to: u32 = 0;

    // Coordinates of the circle-center.
    var c_x: u32 = 0;
    var c_y: u32 = 0;

    // For a given y there are up to two solutions for the circle-equation.
    // Set to -1 for the left, and 1 for the right hemisphere.
    var circle_hemisphere: i32 = 0;

    // The quarter circle only has to be evaluated for a small range of
    // y-values.
    var y_min: u32 = 0;
    var y_max: u32 = 0;

    switch (cp) {
        '╭' => {
            // Don't use supersampled coordinates yet, we want to align actual
            // pixels.
            //
            // pixel-coordinates of the lower edge of the right line and the
            // right edge of the bottom line.
            const right_bottom_edge = (height_pixels + thick_pixels) / 2;
            const bottom_right_edge = (width_pixels + thick_pixels) / 2;

            // find coordinates of circle-center.
            c_y = right_bottom_edge + circle_inner_edge;
            c_x = bottom_right_edge + circle_inner_edge;

            // we want to render the left, not the right hemisphere of the circle.
            circle_hemisphere = -1;

            // don't evaluate beyond c_y, the vertical line is drawn there.
            y_min = 0;
            y_max = c_y;

            // the vertical line should extend to the bottom of the box, the
            // horizontal to the right.
            vert_to = height_pixels;
            hor_to = width_pixels;
        },
        '╮' => {
            const left_bottom_edge = (height_pixels + thick_pixels) / 2;
            const bottom_left_edge = (width_pixels - thick_pixels) / 2;

            c_y = left_bottom_edge + circle_inner_edge;
            c_x = bottom_left_edge - circle_inner_edge;

            circle_hemisphere = 1;

            y_min = 0;
            y_max = c_y;

            vert_to = height_pixels;
            hor_to = 0;
        },
        '╰' => {
            const right_top_edge = (height_pixels - thick_pixels) / 2;
            const top_right_edge = (width_pixels + thick_pixels) / 2;

            c_y = right_top_edge - circle_inner_edge;
            c_x = top_right_edge + circle_inner_edge;

            circle_hemisphere = -1;

            y_min = c_y;
            y_max = height_pixels;

            vert_to = 0;
            hor_to = width_pixels;
        },
        '╯' => {
            const left_top_edge = (height_pixels - thick_pixels) / 2;
            const top_left_edge = (width_pixels - thick_pixels) / 2;

            c_y = left_top_edge - circle_inner_edge;
            c_x = top_left_edge - circle_inner_edge;

            circle_hemisphere = 1;

            y_min = c_y;
            y_max = height_pixels;

            vert_to = 0;
            hor_to = 0;
        },

        else => {},
    }

    // store for horizontal+vertical line.
    const c_x_pixels = c_x;
    const c_y_pixels = c_y;

    // Bring coordinates from pixel-grid to supersampled grid.
    c_r *= supersample;
    c_x *= supersample;
    c_y *= supersample;

    y_min *= supersample;
    y_max *= supersample;

    const c_r2 = c_r * c_r;

    // To prevent gaps in the circle, each pixel is sampled multiple times.
    // As the quartercircle ends (vertically) in the middle of a pixel, an
    // uneven number helps hit that exactly.
    {
        var i: f64 = @intToFloat(f64, y_min) * 16;
        while (i <= @intToFloat(f64, y_max) * 16) : (i += 1) {
            const y = i / 16;
            const x = x: {
                // circle_hemisphere * sqrt(c_r2 - (y - c_y) * (y - c_y)) + c_x;
                const hemi = @intToFloat(f64, circle_hemisphere);
                const y_part = y - @intToFloat(f64, c_y);
                const y_squared = y_part * y_part;
                const sqrt = @sqrt(c_r2 - y_squared);
                const f_c_x = @intToFloat(f64, c_x);

                // We need to detect overflows and just skip this i
                const a = hemi * sqrt;
                const b = a + f_c_x;

                // If the float math didn't work, ignore.
                if (std.math.isNan(b)) continue;

                break :x b;
            };

            const row = @floatToInt(i32, @round(y));
            const col = @floatToInt(i32, @round(x));
            if (col < 0) continue;

            // rectangle big enough to fit entire circle with radius thick/2.
            const row1 = row - @intCast(i32, thick / 2 + 1);
            const row2 = row + @intCast(i32, thick / 2 + 1);
            const col1 = col - @intCast(i32, thick / 2 + 1);
            const col2 = col + @intCast(i32, thick / 2 + 1);

            const row_start = @min(row1, row2);
            const row_end = @max(row1, row2);
            const col_start = @min(col1, col2);
            const col_end = @max(col1, col2);

            assert(row_end > row_start);
            assert(col_end > col_start);

            // draw circle with radius thick/2 around x,y.
            // this is accomplished by rejecting pixels where the distance from
            // their center to x,y is greater than thick/2.
            var r: i32 = @max(row_start, 0);
            const r_end = @max(@min(row_end, @intCast(i32, height)), 0);
            while (r < r_end) : (r += 1) {
                const r_midpoint = @intToFloat(f64, r) + 0.5;

                var c: i32 = @max(col_start, 0);
                const c_end = @max(@min(col_end, @intCast(i32, width)), 0);
                while (c < c_end) : (c += 1) {
                    const c_midpoint = @intToFloat(f64, c) + 0.5;

                    // vector from point on quartercircle to midpoint of the current pixel.
                    const center_midpoint_x = c_midpoint - x;
                    const center_midpoint_y = r_midpoint - y;

                    // distance from current point to circle-center.
                    const dist = @sqrt(center_midpoint_x * center_midpoint_x + center_midpoint_y * center_midpoint_y);
                    // skip if midpoint of pixel is outside the circle.
                    if (dist > @intToFloat(f64, thick) / 2) continue;

                    const idx = @intCast(usize, r * stride + c);
                    data[idx] = 0xff;
                }
            }
        }
    }

    // Downsample
    {
        // We want to convert our []u32 to []u8 since we use an 8bpp format
        var data_u32 = img.getData();
        const len_u8 = data_u32.len * 4;
        var real_data = @alignCast(@alignOf(u8), @ptrCast([*]u8, data_u32.ptr)[0..len_u8]);
        const real_stride = img.getStride();

        var r: u32 = 0;
        while (r < self.height) : (r += 1) {
            var c: u32 = 0;
            while (c < self.width) : (c += 1) {
                var total: u32 = 0;
                var i: usize = 0;
                while (i < supersample) : (i += 1) {
                    var j: usize = 0;
                    while (j < supersample) : (j += 1) {
                        const idx = (r * supersample + i) * @intCast(usize, stride) + c * supersample + j;
                        total += data[idx];
                    }
                }

                const average = @intCast(u8, @min(total / (supersample * supersample), 0xff));
                const idx = r * @intCast(usize, real_stride) + c;
                real_data[idx] = average;
            }
        }
    }

    // draw vertical/horizontal lines from quartercircle-edge to box-edge.
    self.vline(img, @min(c_y_pixels, vert_to), @max(c_y_pixels, vert_to), (width_pixels - thick_pixels) / 2, thick_pixels);
    self.hline(img, @min(c_x_pixels, hor_to), @max(c_x_pixels, hor_to), (height_pixels - thick_pixels) / 2, thick_pixels);
}

fn draw_dash_horizontal(
    self: Box,
    img: *pixman.Image,
    count: u8,
    thick_px: u32,
    gap: u32,
) void {
    assert(count >= 2 and count <= 4);

    // The number of gaps we have is one less than the number of dashes.
    // "- - -" => 2 gaps
    const gap_count = count - 1;

    // Determine the width of our dashes
    const dash_width = dash_width: {
        var gap_i = gap;
        var dash_width = (self.width - (gap_count * gap_i)) / count;
        while (dash_width <= 0 and gap_i > 1) {
            gap_i -= 1;
            dash_width = (self.width - (gap_count * gap_i)) / count;
        }

        // If we can't fit any dashes then we just render a horizontal line.
        if (dash_width <= 0) {
            self.hline_middle(img, .light);
            return;
        }

        break :dash_width dash_width;
    };

    // Our total width should be less than our real width
    assert(count * dash_width + gap_count * gap <= self.width);
    const remaining = self.width - count * dash_width - gap_count * gap;

    var x: [4]u32 = .{0} ** 4;
    var w: [4]u32 = .{dash_width} ** 4;
    x[1] = x[0] + w[0] + gap;
    if (count == 2)
        w[1] = self.width - x[1]
    else if (count == 3)
        w[1] += remaining
    else
        w[1] += remaining / 2;

    if (count >= 3) {
        x[2] = x[1] + w[1] + gap;
        if (count == 3)
            w[2] = self.width - x[2]
        else
            w[2] += remaining - remaining / 2;
    }

    if (count >= 4) {
        x[3] = x[2] + w[2] + gap;
        w[3] = self.width - x[3];
    }

    self.hline(img, x[0], x[0] + w[0], (self.height - thick_px) / 2, thick_px);
    self.hline(img, x[1], x[1] + w[1], (self.height - thick_px) / 2, thick_px);
    if (count >= 3)
        self.hline(img, x[2], x[2] + w[2], (self.height - thick_px) / 2, thick_px);
    if (count >= 4)
        self.hline(img, x[3], x[3] + w[3], (self.height - thick_px) / 2, thick_px);
}

fn draw_dash_vertical(
    self: Box,
    img: *pixman.Image,
    count: u8,
    thick_px: u32,
    gap: u32,
) void {
    assert(count >= 2 and count <= 4);

    // The number of gaps we have is one less than the number of dashes.
    // "- - -" => 2 gaps
    const gap_count = count - 1;

    // Determine the height of our dashes
    const dash_height = dash_height: {
        var gap_i = gap;
        var dash_height = (self.height - (gap_count * gap_i)) / count;
        while (dash_height <= 0 and gap_i > 1) {
            gap_i -= 1;
            dash_height = (self.height - (gap_count * gap_i)) / count;
        }

        // If we can't fit any dashes then we just render a horizontal line.
        if (dash_height <= 0) {
            self.vline_middle(img, .light);
            return;
        }

        break :dash_height dash_height;
    };

    // Our total height should be less than our real height
    assert(count * dash_height + gap_count * gap <= self.height);
    const remaining = self.height - count * dash_height - gap_count * gap;

    var y: [4]u32 = .{0} ** 4;
    var h: [4]u32 = .{dash_height} ** 4;
    y[1] = y[0] + h[0] + gap;
    if (count == 2)
        h[1] = self.height - y[1]
    else if (count == 3)
        h[1] += remaining
    else
        h[1] += remaining / 2;

    if (count >= 3) {
        y[2] = y[1] + h[1] + gap;
        if (count == 3)
            h[2] = self.height - y[2]
        else
            h[2] += remaining - remaining / 2;
    }

    if (count >= 4) {
        y[3] = y[2] + h[2] + gap;
        h[3] = self.height - y[3];
    }

    self.vline(img, y[0], y[0] + h[0], (self.width - thick_px) / 2, thick_px);
    self.vline(img, y[1], y[1] + h[1], (self.width - thick_px) / 2, thick_px);
    if (count >= 3)
        self.vline(img, y[2], y[2] + h[2], (self.width - thick_px) / 2, thick_px);
    if (count >= 4)
        self.vline(img, y[3], y[3] + h[3], (self.width - thick_px) / 2, thick_px);
}

fn vline_middle(self: Box, img: *pixman.Image, thickness: Thickness) void {
    const thick_px = thickness.height(self.thickness);
    self.vline(img, 0, self.height, (self.width - thick_px) / 2, thick_px);
}

fn vline_middle_up(
    self: Box,
    img: *pixman.Image,
    vthickness: Thickness,
    hthickness: Thickness,
) void {
    const hthick_px = hthickness.height(self.thickness);
    const vthick_px = vthickness.height(self.thickness);
    self.vline(
        img,
        0,
        (self.height + hthick_px) / 2,
        (self.width - vthick_px) / 2,
        vthick_px,
    );
}

fn vline_middle_down(
    self: Box,
    img: *pixman.Image,
    vthickness: Thickness,
    hthickness: Thickness,
) void {
    const hthick_px = hthickness.height(self.thickness);
    const vthick_px = vthickness.height(self.thickness);
    self.vline(
        img,
        (self.height - hthick_px) / 2,
        self.height,
        (self.width - vthick_px) / 2,
        vthick_px,
    );
}

fn hline_middle(self: Box, img: *pixman.Image, thickness: Thickness) void {
    const thick_px = thickness.height(self.thickness);
    self.hline(img, 0, self.width, (self.height - thick_px) / 2, thick_px);
}

fn hline_middle_left(
    self: Box,
    img: *pixman.Image,
    vthickness: Thickness,
    hthickness: Thickness,
) void {
    const hthick_px = hthickness.height(self.thickness);
    const vthick_px = vthickness.height(self.thickness);
    self.hline(
        img,
        0,
        (self.width + vthick_px) / 2,
        (self.height - hthick_px) / 2,
        hthick_px,
    );
}

fn hline_middle_right(
    self: Box,
    img: *pixman.Image,
    vthickness: Thickness,
    hthickness: Thickness,
) void {
    const hthick_px = hthickness.height(self.thickness);
    const vthick_px = vthickness.height(self.thickness);
    self.hline(
        img,
        (self.width - vthick_px) / 2,
        self.width,
        (self.height - hthick_px) / 2,
        hthick_px,
    );
}

fn vline(
    self: Box,
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
    self: Box,
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

fn rect(
    self: Box,
    img: *pixman.Image,
    x1: u32,
    y1: u32,
    x2: u32,
    y2: u32,
) void {
    const boxes = &[_]pixman.Box32{
        .{
            .x1 = @intCast(i32, @min(@max(x1, 0), self.width)),
            .y1 = @intCast(i32, @min(@max(y1, 0), self.height)),
            .x2 = @intCast(i32, @min(@max(x2, 0), self.width)),
            .y2 = @intCast(i32, @min(@max(y2, 0), self.height)),
        },
    };

    img.fillBoxes(.src, white, boxes) catch {};
}

test "all" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cp: u32 = 0x2500;
    const end = 0x2570;
    while (cp <= end) : (cp += 1) {
        var atlas_greyscale = try Atlas.init(alloc, 512, .greyscale);
        defer atlas_greyscale.deinit(alloc);

        const face: Box = .{ .width = 18, .height = 36, .thickness = 2 };
        const glyph = try face.renderGlyph(
            alloc,
            &atlas_greyscale,
            cp,
        );
        try testing.expectEqual(@as(u32, face.width), glyph.width);
        try testing.expectEqual(@as(u32, face.height), glyph.height);
    }
}
