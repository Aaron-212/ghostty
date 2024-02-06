//! This benchmark tests the throughput of the VT stream. It has a few
//! modes in order to test different methods of stream processing. It
//! provides a "noop" mode to give us the `memcpy` speed.
//!
//! This will consume all of the available stdin, so you should run it
//! with `head` in a pipe to restrict. For example, to test ASCII input:
//!
//!   bench-stream --mode=gen-ascii | head -c 50M | bench-stream --mode=simd
//!

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const cli = @import("../cli.zig");
const terminal = @import("../terminal/main.zig");

const Args = struct {
    mode: Mode = .noop,

    /// Process input with a real terminal. This will be MUCH slower than
    /// the other modes because it has to maintain terminal state but will
    /// help get more realistic numbers.
    terminal: bool = false,
    @"terminal-rows": usize = 80,
    @"terminal-cols": usize = 120,

    /// This is set by the CLI parser for deinit.
    _arena: ?ArenaAllocator = null,

    pub fn deinit(self: *Args) void {
        if (self._arena) |arena| arena.deinit();
        self.* = undefined;
    }
};

const Mode = enum {
    // Do nothing, just read from stdin into a stack-allocated buffer.
    // This is used to benchmark our base-case: it gives us our maximum
    // throughput on a basic read.
    noop,

    // These benchmark the throughput of the terminal stream parsing
    // with and without SIMD. The "simd" option will use whatever is best
    // for the running platform.
    //
    // Note that these run through the full VT parser but do not apply
    // the operations to terminal state, so there is no terminal state
    // overhead.
    scalar,
    simd,

    // Generate an infinite stream of random printable ASCII characters.
    @"gen-ascii",
};

pub const std_options = struct {
    pub const log_level: std.log.Level = .debug;
};

pub fn main() !void {
    // We want to use the c allocator because it is much faster than GPA.
    const alloc = std.heap.c_allocator;

    // Parse our args
    var args: Args = .{};
    defer args.deinit();
    {
        var iter = try std.process.argsWithAllocator(alloc);
        defer iter.deinit();
        try cli.args.parse(Args, alloc, &args, &iter);
    }

    const reader = std.io.getStdIn().reader();
    const writer = std.io.getStdOut().writer();

    // Handle the modes that do not depend on terminal state first.
    switch (args.mode) {
        .@"gen-ascii" => try genAscii(writer),
        .noop => try benchNoop(alloc, reader),

        // Handle the ones that depend on terminal state next
        inline .scalar,
        .simd,
        => |tag| {
            if (args.terminal) {
                const TerminalStream = terminal.Stream(*TerminalHandler);
                var t = try terminal.Terminal.init(
                    alloc,
                    args.@"terminal-cols",
                    args.@"terminal-rows",
                );
                var handler: TerminalHandler = .{ .t = &t };
                var stream: TerminalStream = .{ .handler = &handler };
                switch (tag) {
                    .scalar => try benchScalar(alloc, reader, &stream),
                    .simd => try benchSimd(alloc, reader, &stream),
                    else => @compileError("missing case"),
                }
            } else {
                var stream: terminal.Stream(NoopHandler) = .{ .handler = .{} };
                switch (tag) {
                    .scalar => try benchScalar(alloc, reader, &stream),
                    .simd => try benchSimd(alloc, reader, &stream),
                    else => @compileError("missing case"),
                }
            }
        },
    }
}

/// Generates an infinite stream of random printable ASCII characters.
/// This has no control characters in it at all.
fn genAscii(writer: anytype) !void {
    const alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{}|;':\\\",./<>?`~";
    try genData(writer, alphabet);
}

/// Generates an infinite stream of bytes from the given alphabet.
fn genData(writer: anytype, alphabet: []const u8) !void {
    var prng = std.rand.DefaultPrng.init(0x12345678);
    const rnd = prng.random();
    while (true) {
        var buf: [1024]u8 = undefined;
        for (&buf) |*c| {
            const idx = rnd.uintLessThanBiased(usize, alphabet.len);
            c.* = alphabet[idx];
        }

        writer.writeAll(&buf) catch |err| switch (err) {
            error.BrokenPipe => return, // stdout closed
            else => return err,
        };
    }
}

fn benchNoop(alloc: Allocator, reader: anytype) !void {
    // Large-ish buffer because we don't want to be benchmarking
    // heap allocation as much as possible. We purposely leak this
    // memory because we don't want to benchmark a free cost
    // either.
    const buf = try alloc.alloc(u8, 1024 * 1024 * 16);
    var total: usize = 0;
    while (true) {
        const n = try reader.readAll(buf);
        if (n == 0) break;
        total += n;
    }

    std.log.info("total bytes len={}", .{total});
}

fn benchScalar(alloc: Allocator, reader: anytype, stream: anytype) !void {
    _ = alloc;

    var buf: [4096]u8 = undefined;
    while (true) {
        const n = try reader.read(&buf);
        if (n == 0) break;

        // Using stream.next directly with a for loop applies a naive
        // scalar approach.
        for (buf[0..n]) |c| try stream.next(c);
    }
}

fn benchSimd(alloc: Allocator, reader: anytype, stream: anytype) !void {
    _ = alloc;

    var buf: [4096]u8 = undefined;
    while (true) {
        const n = try reader.read(&buf);
        if (n == 0) break;
        try stream.nextSlice(buf[0..n]);
    }
}

const NoopHandler = struct {
    pub fn print(self: NoopHandler, cp: u21) !void {
        _ = self;
        _ = cp;
    }
};

const TerminalHandler = struct {
    t: *terminal.Terminal,

    pub fn print(self: *TerminalHandler, cp: u21) !void {
        try self.t.print(cp);
    }
};
