const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const font = @import("../font/main.zig");
const renderer = @import("../renderer.zig");

/// The messages that can be sent to a renderer thread.
pub const Message = union(enum) {
    /// A change in state in the window focus that this renderer is
    /// rendering within. This is only sent when a change is detected so
    /// the renderer is expected to handle all of these.
    focus: bool,

    /// Reset the cursor blink by immediately showing the cursor then
    /// restarting the timer.
    reset_cursor_blink: void,

    /// Change the font size. This should recalculate the grid size and
    /// send a grid size change message back to the window thread if
    /// the size changes.
    font_size: font.face.DesiredSize,

    /// Change the screen size.
    screen_size: renderer.ScreenSize,

    /// The derived configuration to update the renderer with.
    change_config: renderer.Renderer.DerivedConfig,
};
