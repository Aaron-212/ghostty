const Loop = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const c = @import("c.zig");
const errors = @import("error.zig");

loop: *c.uv_loop_t,

/// Initialize a new uv_loop.
pub fn init(alloc: Allocator) !Loop {
    // The uv_loop_t type MUST be heap allocated and must not be copied.
    // I can't find a definitive source on this, but the test suite starts
    // hanging in weird places and doing bad things when it is copied.
    const loop = try alloc.create(c.uv_loop_t);
    try errors.convertError(c.uv_loop_init(loop));
    return Loop{ .loop = loop };
}

/// Releases all internal loop resources. Call this function only when the
/// loop has finished executing and all open handles and requests have been
/// closed, or this will silently fail (in debug mode it will panic).
pub fn deinit(self: *Loop, alloc: Allocator) void {
    // deinit functions idiomatically cannot fail in Zig, so we do the
    // next best thing here and assert so that in debug mode you'll get
    // a crash.
    std.debug.assert(c.uv_loop_close(self.loop) >= 0);
    alloc.destroy(self.loop);
    self.* = undefined;
}

/// Returns true if the loop is still alive.
pub fn alive(self: Loop) !bool {
    const res = c.uv_loop_alive(self.loop);
    try errors.convertError(res);
    return res > 0;
}

/// This function runs the event loop. See RunMode for mode documentation.
///
/// This is not reentrant. It must not be called from a callback.
pub fn run(self: Loop, mode: RunMode) !u32 {
    const res = c.uv_run(self.loop, @enumToInt(mode));
    try errors.convertError(res);
    return @intCast(u32, res);
}

/// Get backend file descriptor. Only kqueue, epoll and event ports are supported.
///
/// This can be used in conjunction with uv_run(loop, UV_RUN_NOWAIT) to poll
/// in one thread and run the event loop’s callbacks in another see
/// test/test-embed.c for an example.
pub fn backendFd(self: Loop) !c_int {
    const res = c.uv_backend_fd(self.loop);
    try errors.convertError(res);
    return res;
}

/// Get the poll timeout. The return value is in milliseconds, or -1 for no
/// timeout.
pub fn backendTimeout(self: Loop) c_int {
    return c.uv_backend_timeout(self.loop);
}

/// Mode used to run the loop with uv_run().
pub const RunMode = enum(c.uv_run_mode) {
    default = c.UV_RUN_DEFAULT,
    once = c.UV_RUN_ONCE,
    nowait = c.UV_RUN_NOWAIT,
};

test {
    var loop = try init(testing.allocator);
    defer loop.deinit(testing.allocator);

    try testing.expect((try loop.backendFd()) > 0);
    try testing.expectEqual(@as(u32, 0), try loop.run(.nowait));
}
