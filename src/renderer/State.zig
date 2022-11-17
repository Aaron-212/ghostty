//! This is the render state that is given to a renderer.

const std = @import("std");
const Allocator = std.mem.Allocator;
const DevMode = @import("../DevMode.zig");
const terminal = @import("../terminal/main.zig");
const renderer = @import("../renderer.zig");

/// The mutex that must be held while reading any of the data in the
/// members of this state. Note that the state itself is NOT protected
/// by the mutex and is NOT thread-safe, only the members values of the
/// state (i.e. the terminal, devmode, etc. values).
mutex: *std.Thread.Mutex,

/// Cursor configuration for rendering
cursor: Cursor,

/// The terminal data.
terminal: *terminal.Terminal,

/// The devmode data.
devmode: ?*const DevMode = null,

pub const Cursor = struct {
    /// Current cursor style. This can be set by escape sequences. To get
    /// the default style, the config has to be referenced.
    style: terminal.CursorStyle = .default,

    /// Whether the cursor is visible at all. This should not be used for
    /// "blink" settings, see "blink" for that. This is used to turn the
    /// cursor ON or OFF.
    visible: bool = true,
};
