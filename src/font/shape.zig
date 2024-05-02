const builtin = @import("builtin");
const options = @import("main.zig").options;
pub const noop = @import("shaper/noop.zig");
pub const harfbuzz = @import("shaper/harfbuzz.zig");
pub const coretext = @import("shaper/coretext.zig");
pub const web_canvas = @import("shaper/web_canvas.zig");
pub usingnamespace @import("shaper/run.zig");
pub const Cache = @import("shaper/Cache.zig");

/// Shaper implementation for our compile options.
pub const Shaper = switch (options.backend) {
    .freetype,
    .fontconfig_freetype,
    .coretext_freetype,
    .coretext_harfbuzz,
    => harfbuzz.Shaper,

    // Note that coretext_freetype cannot use the coretext
    // shaper because the coretext shaper requests CoreText
    // font faces.
    .coretext => coretext.Shaper,

    .coretext_noshape => noop.Shaper,

    .web_canvas => web_canvas.Shaper,
};

/// A cell is a single single within a terminal that should be rendered
/// for a shaping call. Note all terminal cells may be present; only
/// cells that have a glyph that needs to be rendered.
pub const Cell = struct {
    /// The column that this cell occupies. Since a set of shaper cells is
    /// always on the same line, only the X is stored. It is expected the
    /// caller has access to the original screen cell.
    x: u16,

    /// An additional offset to apply to the rendering.
    x_offset: i16 = 0,
    y_offset: i16 = 0,

    /// The glyph index for this cell. The font index to use alongside
    /// this cell is available in the text run. This glyph index is only
    /// valid for a given GroupCache and FontIndex that was used to create
    /// the runs.
    ///
    /// If this is null then this is an empty cell. If there are styles
    /// then those should be applied but there is no glyph to render.
    glyph_index: ?u32,
};

/// Options for shapers.
pub const Options = struct {
    /// Font features to use when shaping. These can be in the following
    /// formats: "-feat" "+feat" "feat". A "-"-prefix is used to disable
    /// a feature and the others are used to enable a feature. If a feature
    /// isn't supported or is invalid, it will be ignored.
    ///
    /// Note: eventually, this will move to font.Face probably as we may
    /// want to support per-face feature configuration. For now, we only
    /// support applying features globally.
    features: []const []const u8 = &.{},
};

test {
    _ = Cache;
    _ = Shaper;

    // Always test noop
    _ = noop;
}
