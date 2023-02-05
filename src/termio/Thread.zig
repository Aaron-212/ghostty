//! Represents the IO thread logic. The IO thread is responsible for
//! the child process and pty management.
pub const Thread = @This();

const std = @import("std");
const builtin = @import("builtin");
const xev = @import("xev");
const termio = @import("../termio.zig");
const BlockingQueue = @import("../blocking_queue.zig").BlockingQueue;
const tracy = @import("tracy");
const trace = tracy.trace;

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.io_thread);

/// The type used for sending messages to the IO thread. For now this is
/// hardcoded with a capacity. We can make this a comptime parameter in
/// the future if we want it configurable.
const Mailbox = BlockingQueue(termio.Message, 64);

/// Allocator used for some state
alloc: std.mem.Allocator,

/// The main event loop for the thread. The user data of this loop
/// is always the allocator used to create the loop. This is a convenience
/// so that users of the loop always have an allocator.
loop: xev.Loop,

/// This can be used to wake up the thread.
wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

/// This can be used to stop the thread on the next loop iteration.
stop: xev.Async,
stop_c: xev.Completion = .{},

/// The underlying IO implementation.
impl: *termio.Impl,

/// The mailbox that can be used to send this thread messages. Note
/// this is a blocking queue so if it is full you will get errors (or block).
mailbox: *Mailbox,

/// Initialize the thread. This does not START the thread. This only sets
/// up all the internal state necessary prior to starting the thread. It
/// is up to the caller to start the thread with the threadMain entrypoint.
pub fn init(
    alloc: Allocator,
    impl: *termio.Impl,
) !Thread {
    // Create our event loop.
    var loop = try xev.Loop.init(.{});
    errdefer loop.deinit();

    // This async handle is used to "wake up" the renderer and force a render.
    var wakeup_h = try xev.Async.init();
    errdefer wakeup_h.deinit();

    // This async handle is used to stop the loop and force the thread to end.
    var stop_h = try xev.Async.init();
    errdefer stop_h.deinit();

    // The mailbox for messaging this thread
    var mailbox = try Mailbox.create(alloc);
    errdefer mailbox.destroy(alloc);

    return Thread{
        .alloc = alloc,
        .loop = loop,
        .wakeup = wakeup_h,
        .stop = stop_h,
        .impl = impl,
        .mailbox = mailbox,
    };
}

/// Clean up the thread. This is only safe to call once the thread
/// completes executing; the caller must join prior to this.
pub fn deinit(self: *Thread) void {
    self.stop.deinit();
    self.wakeup.deinit();
    self.loop.deinit();

    // Nothing can possibly access the mailbox anymore, destroy it.
    self.mailbox.destroy(self.alloc);
}

/// The main entrypoint for the thread.
pub fn threadMain(self: *Thread) void {
    // Call child function so we can use errors...
    self.threadMain_() catch |err| {
        // In the future, we should expose this on the thread struct.
        log.warn("error in io thread err={}", .{err});
    };
}

fn threadMain_(self: *Thread) !void {
    tracy.setThreadName("pty io");

    // Run our thread start/end callbacks. This allows the implementation
    // to hook into the event loop as needed.
    var data = try self.impl.threadEnter(&self.loop);
    defer data.deinit();
    defer self.impl.threadExit(data);

    // Start the async handlers
    self.wakeup.wait(&self.loop, &self.wakeup_c, Thread, self, wakeupCallback);
    self.stop.wait(&self.loop, &self.stop_c, Thread, self, stopCallback);

    // Run
    log.debug("starting IO thread", .{});
    defer log.debug("exiting IO thread", .{});
    try self.loop.run(.until_done);
}

/// Drain the mailbox, handling all the messages in our terminal implementation.
fn drainMailbox(self: *Thread) !void {
    const zone = trace(@src());
    defer zone.end();

    // This holds the mailbox lock for the duration of the drain. The
    // expectation is that all our message handlers will be non-blocking
    // ENOUGH to not mess up throughput on producers.
    var redraw: bool = false;
    while (self.mailbox.pop()) |message| {
        // If we have a message we always redraw
        redraw = true;

        log.debug("mailbox message={}", .{message});
        switch (message) {
            .resize => |v| try self.impl.resize(v.grid_size, v.screen_size, v.padding),
            .write_small => |v| try self.impl.queueWrite(v.data[0..v.len]),
            .write_stable => |v| try self.impl.queueWrite(v),
            .write_alloc => |v| {
                defer v.alloc.free(v.data);
                try self.impl.queueWrite(v.data);
            },
        }
    }

    // Trigger a redraw after we've drained so we don't waste cyces
    // messaging a redraw.
    if (redraw) {
        try self.impl.renderer_wakeup.notify();
    }
}

fn wakeupCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch |err| {
        log.err("error in wakeup err={}", .{err});
        return .rearm;
    };

    const zone = trace(@src());
    defer zone.end();

    const t = self_.?;

    // When we wake up, we check the mailbox. Mailbox producers should
    // wake up our thread after publishing.
    t.drainMailbox() catch |err|
        log.err("error draining mailbox err={}", .{err});

    return .rearm;
}

fn stopCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch unreachable;
    self_.?.loop.stop();
    return .disarm;
}
