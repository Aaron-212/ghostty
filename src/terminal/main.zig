const stream = @import("stream.zig");
const ansi = @import("ansi.zig");
const csi = @import("csi.zig");
const sgr = @import("sgr.zig");
pub const color = @import("color.zig");

pub const Terminal = @import("Terminal.zig");
pub const Parser = @import("Parser.zig");
pub const Stream = stream.Stream;
pub const CursorStyle = ansi.CursorStyle;
pub const DeviceAttributeReq = ansi.DeviceAttributeReq;
pub const DeviceStatusReq = ansi.DeviceStatusReq;
pub const Mode = ansi.Mode;
pub const EraseDisplay = csi.EraseDisplay;
pub const EraseLine = csi.EraseLine;
pub const Attribute = sgr.Attribute;

// Not exported because they're just used for tests.

test {
    _ = ansi;
    _ = color;
    _ = csi;
    _ = sgr;
    _ = stream;
    _ = Parser;
    _ = Terminal;

    _ = @import("osc.zig");
    _ = @import("parse_table.zig");
    _ = @import("Screen.zig");
    _ = @import("Tabstops.zig");
}
