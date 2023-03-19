//! The options that are used to configure a terminal IO implementation.

const xev = @import("xev");
const apprt = @import("../apprt.zig");
const renderer = @import("../renderer.zig");
const Config = @import("../config.zig").Config;

/// The size of the terminal grid.
grid_size: renderer.GridSize,

/// The size of the viewport in pixels.
screen_size: renderer.ScreenSize,

/// The app configuration. This must NOT be stored by any termio implementation.
/// The memory it points to is NOT stable after the init call so any values
/// in here must be copied.
config: *const Config,

/// The render state. The IO implementation can modify anything here. The
/// surface thread will setup the initial "terminal" pointer but the IO impl
/// is free to change that if that is useful (i.e. doing some sort of dual
/// terminal implementation.)
renderer_state: *renderer.State,

/// A handle to wake up the renderer. This hints to the renderer that that
/// a repaint should happen.
renderer_wakeup: xev.Async,

/// The mailbox for renderer messages.
renderer_mailbox: *renderer.Thread.Mailbox,

/// The mailbox for sending the surface messages.
surface_mailbox: apprt.surface.Mailbox,
