const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const configpkg = @import("../config.zig");
const font = @import("../font/main.zig");
const renderer = @import("../renderer.zig");
const terminal = @import("../terminal/main.zig");

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

    /// Change the foreground color. This can be done separately from changing
    /// the config file in response to an OSC 10 command.
    foreground_color: terminal.color.RGB,

    /// Change the background color. This can be done separately from changing
    /// the config file in response to an OSC 11 command.
    background_color: terminal.color.RGB,

    /// Change the cursor color. This can be done separately from changing the
    /// config file in response to an OSC 12 command.
    cursor_color: ?terminal.color.RGB,

    /// Changes the screen size.
    resize: struct {
        /// The full screen (drawable) size. This does NOT include padding.
        screen_size: renderer.ScreenSize,

        /// The explicit padding values.
        padding: renderer.Padding,
    },

    /// The derived configuration to update the renderer with.
    change_config: struct {
        alloc: Allocator,
        thread: *renderer.Thread.DerivedConfig,
        impl: *renderer.Renderer.DerivedConfig,
    },

    /// Activate or deactivate the inspector.
    inspector: bool,

    /// Initialize a change_config message.
    pub fn initChangeConfig(alloc: Allocator, config: *const configpkg.Config) !Message {
        const thread_ptr = try alloc.create(renderer.Thread.DerivedConfig);
        errdefer alloc.destroy(thread_ptr);
        const config_ptr = try alloc.create(renderer.Renderer.DerivedConfig);
        errdefer alloc.destroy(config_ptr);

        thread_ptr.* = renderer.Thread.DerivedConfig.init(config);
        config_ptr.* = try renderer.Renderer.DerivedConfig.init(alloc, config);
        errdefer config_ptr.deinit();

        return .{
            .change_config = .{
                .alloc = alloc,
                .thread = thread_ptr,
                .impl = config_ptr,
            },
        };
    }

    pub fn deinit(self: *const Message) void {
        switch (self.*) {
            .change_config => |v| {
                v.impl.deinit();
                v.alloc.destroy(v.impl);
                v.alloc.destroy(v.thread);
            },

            else => {},
        }
    }
};
