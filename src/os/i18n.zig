const std = @import("std");
const build_config = @import("../build_config.zig");

const log = std.log.scoped(.i18n);

/// Supported locales for the application. This must be kept up to date
/// with the translations available in the `po/` directory; this is used
/// by our build process as well runtime libghostty APIs.
pub const locales = [_][]const u8{
    "zh_CN.UTF-8",
};

pub const InitError = error{
    InvalidResourcesDir,
    OutOfMemory,
};

/// Initialize i18n support for the application. This should be
/// called automatically by the global state initialization
/// in global.zig.
///
/// This calls `bindtextdomain` for gettext with the proper directory
/// of translations. This does NOT call `textdomain` as we don't
/// want to set the domain for the entire application since this is also
/// used by libghostty.
pub fn init(resources_dir: []const u8) InitError!void {
    // Our resources dir is always nested below the share dir that
    // is standard for translations.
    const share_dir = std.fs.path.dirname(resources_dir) orelse
        return error.InvalidResourcesDir;

    // Build our locale path
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrintZ(&buf, "{s}/locale", .{share_dir}) catch
        return error.OutOfMemory;

    // Bind our bundle ID to the given locale path
    log.debug("binding domain={s} path={s}", .{ build_config.bundle_id, path });
    _ = bindtextdomain(build_config.bundle_id, path.ptr) orelse
        return error.OutOfMemory;
}

/// Translate a message for the Ghostty domain.
pub fn _(msgid: [*:0]const u8) [*:0]const u8 {
    return dgettext(build_config.bundle_id, msgid);
}

// Manually include function definitions for the gettext functions
// as libintl.h isn't always easily available (e.g. in musl)
extern fn bindtextdomain(domainname: [*:0]const u8, dirname: [*:0]const u8) ?[*:0]const u8;
extern fn textdomain(domainname: [*:0]const u8) ?[*:0]const u8;
extern fn gettext(msgid: [*:0]const u8) [*:0]const u8;
extern fn dgettext(domainname: [*:0]const u8, msgid: [*:0]const u8) [*:0]const u8;
