pub const lut = @import("lut.zig");

pub usingnamespace @import("grapheme.zig");
const props = @import("props.zig");
pub const table = props.table;
pub const Properties = props.Properties;

test {
    @import("std").testing.refAllDecls(@This());
}
