const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const point = @import("../point.zig");
const command = @import("graphics_command.zig");
const Image = @import("graphics_image.zig").Image;
const Command = command.Command;
const ScreenPoint = point.ScreenPoint;

/// An image storage is associated with a terminal screen (i.e. main
/// screen, alt screen) and contains all the transmitted images and
/// placements.
pub const ImageStorage = struct {
    const ImageMap = std.AutoHashMapUnmanaged(u32, Image);
    const PlacementMap = std.AutoHashMapUnmanaged(PlacementKey, Placement);

    /// The set of images that are currently known.
    images: ImageMap = .{},

    /// The set of placements for loaded images.
    placements: PlacementMap = .{},

    pub fn deinit(self: *ImageStorage, alloc: Allocator) void {
        var it = self.images.iterator();
        while (it.next()) |kv| kv.value_ptr.deinit(alloc);

        self.images.deinit(alloc);
        self.placements.deinit(alloc);
    }

    /// Add an already-loaded image to the storage. This will automatically
    /// free any existing image with the same ID.
    pub fn addImage(self: *ImageStorage, alloc: Allocator, img: Image) Allocator.Error!void {
        const gop = try self.images.getOrPut(alloc, img.id);
        if (gop.found_existing) gop.value_ptr.deinit(alloc);
        gop.value_ptr.* = img;
    }

    /// Add a placement for a given image. The caller must verify in advance
    /// the image exists to prevent memory corruption.
    pub fn addPlacement(
        self: *ImageStorage,
        alloc: Allocator,
        image_id: u32,
        placement_id: u32,
        p: Placement,
    ) !void {
        assert(self.images.get(image_id) != null);

        const key: PlacementKey = .{ .image_id = image_id, .placement_id = placement_id };
        const gop = try self.placements.getOrPut(alloc, key);
        gop.value_ptr.* = p;
    }

    /// Get an image by its ID. If the image doesn't exist, null is returned.
    pub fn imageById(self: *ImageStorage, image_id: u32) ?Image {
        return self.images.get(image_id);
    }

    /// Every placement is uniquely identified by the image ID and the
    /// placement ID. If an image ID isn't specified it is assumed to be 0.
    /// Likewise, if a placement ID isn't specified it is assumed to be 0.
    pub const PlacementKey = struct {
        image_id: u32,
        placement_id: u32,
    };

    pub const Placement = struct {
        /// The location of the image on the screen.
        point: ScreenPoint,
    };
};
