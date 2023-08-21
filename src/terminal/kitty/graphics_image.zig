const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const command = @import("graphics_command.zig");

/// Maximum width or height of an image. Taken directly from Kitty.
const max_dimension = 10000;

/// A chunked image is an image that is in-progress and being constructed
/// using chunks (the "m" parameter in the protocol).
pub const ChunkedImage = struct {
    /// The in-progress image. The first chunk must have all the metadata
    /// so this comes from that initially.
    image: Image,

    /// The data that is being built up.
    data: std.ArrayListUnmanaged(u8) = .{},

    /// Initialize a chunked image from the first image part.
    pub fn init(alloc: Allocator, image: Image) !ChunkedImage {
        // Copy our initial set of data
        var data = try std.ArrayListUnmanaged(u8).initCapacity(alloc, image.data.len * 2);
        errdefer data.deinit(alloc);
        try data.appendSlice(alloc, image.data);

        // Set data to empty so it doesn't get freed.
        var result: ChunkedImage = .{ .image = image, .data = data };
        result.image.data = "";
        return result;
    }

    pub fn deinit(self: *ChunkedImage, alloc: Allocator) void {
        self.image.deinit(alloc);
        self.data.deinit(alloc);
    }

    pub fn destroy(self: *ChunkedImage, alloc: Allocator) void {
        self.deinit(alloc);
        alloc.destroy(self);
    }

    /// Complete the chunked image, returning a completed image.
    pub fn complete(self: *ChunkedImage, alloc: Allocator) !Image {
        var result = self.image;
        result.data = try self.data.toOwnedSlice(alloc);
        self.image = .{};
        return result;
    }
};

/// Image represents a single fully loaded image.
pub const Image = struct {
    id: u32 = 0,
    number: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    format: Format = .rgb,
    data: []const u8 = "",

    pub const Format = enum { rgb, rgba };

    pub const Error = error{
        InvalidData,
        DimensionsRequired,
        DimensionsTooLarge,
        UnsupportedFormat,
        UnsupportedMedium,
    };

    /// Validate that the image appears valid.
    pub fn validate(self: *const Image) !void {
        const bpp: u32 = switch (self.format) {
            .rgb => 3,
            .rgba => 4,
        };

        // Validate our dimensions.
        if (self.width == 0 or self.height == 0) return error.DimensionsRequired;
        if (self.width > max_dimension or self.height > max_dimension) return error.DimensionsTooLarge;

        // Data length must be what we expect
        // NOTE: we use a "<" check here because Kitty itself doesn't validate
        // this and if we validate exact data length then various Kitty
        // applications fail because the test that Kitty documents itself
        // uses an invalid value.
        const expected_len = self.width * self.height * bpp;
        std.log.warn(
            "width={} height={} bpp={} expected_len={} actual_len={}",
            .{ self.width, self.height, bpp, expected_len, self.data.len },
        );
        if (self.data.len < expected_len) return error.InvalidData;
    }

    /// Load an image from a transmission. The data in the command will be
    /// owned by the image if successful. Note that you still must deinit
    /// the command, all the state change will be done internally.
    ///
    /// If the command represents a chunked image then this image will
    /// be incomplete. The caller is expected to inspect the command
    /// and determine if it is a chunked image.
    pub fn load(alloc: Allocator, cmd: *command.Command) !Image {
        const t = cmd.transmission().?;

        // Load the data
        const data = switch (t.medium) {
            .direct => cmd.data,
            else => {
                std.log.warn("unimplemented medium={}", .{t.medium});
                return error.UnsupportedMedium;
            },
        };

        // If we loaded an image successfully then we take ownership
        // of the command data and we need to make sure to clean up on error.
        _ = cmd.toOwnedData();
        errdefer if (data.len > 0) alloc.free(data);

        const img = switch (t.format) {
            .rgb, .rgba => try loadPacked(t, data),
            else => return error.UnsupportedFormat,
        };

        return img;
    }

    /// Load a package image format, i.e. RGB or RGBA.
    fn loadPacked(
        t: command.Transmission,
        data: []const u8,
    ) !Image {
        return Image{
            .id = t.image_id,
            .number = t.image_number,
            .width = t.width,
            .height = t.height,
            .format = switch (t.format) {
                .rgb => .rgb,
                .rgba => .rgba,
                else => unreachable,
            },
            .data = data,
        };
    }

    pub fn deinit(self: *Image, alloc: Allocator) void {
        if (self.data.len > 0) alloc.free(self.data);
    }

    /// Mostly for logging
    pub fn withoutData(self: *const Image) Image {
        var copy = self.*;
        copy.data = "";
        return copy;
    }
};

// This specifically tests we ALLOW invalid RGB data because Kitty
// documents that this should work.
test "image load with invalid RGB data" {
    const testing = std.testing;
    const alloc = testing.allocator;

    // <ESC>_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA<ESC>\
    var cmd: command.Command = .{
        .control = .{ .transmit = .{
            .format = .rgb,
            .width = 1,
            .height = 1,
            .image_id = 31,
        } },
        .data = try alloc.dupe(u8, "AAAA"),
    };
    defer cmd.deinit(alloc);
    var img = try Image.load(alloc, &cmd);
    defer img.deinit(alloc);
}

test "image load with image too wide" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cmd: command.Command = .{
        .control = .{ .transmit = .{
            .format = .rgb,
            .width = max_dimension + 1,
            .height = 1,
            .image_id = 31,
        } },
        .data = try alloc.dupe(u8, "AAAA"),
    };
    defer cmd.deinit(alloc);
    try testing.expectError(error.DimensionsTooLarge, Image.load(alloc, &cmd));
}

test "image load with image too tall" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cmd: command.Command = .{
        .control = .{ .transmit = .{
            .format = .rgb,
            .height = max_dimension + 1,
            .width = 1,
            .image_id = 31,
        } },
        .data = try alloc.dupe(u8, "AAAA"),
    };
    defer cmd.deinit(alloc);
    try testing.expectError(error.DimensionsTooLarge, Image.load(alloc, &cmd));
}
