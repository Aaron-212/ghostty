//! A zig builder step that runs "lipo" on two binaries to create
//! a universal binary.
const LipoStep = @This();

const std = @import("std");
const Step = std.build.Step;
const FileSource = std.build.FileSource;
const GeneratedFile = std.build.GeneratedFile;

pub const Options = struct {
    /// The name of the xcframework to create.
    name: []const u8,

    /// The filename (not the path) of the file to create.
    out_name: []const u8,

    /// Library file (dylib, a) to package.
    input_a: FileSource,
    input_b: FileSource,
};

step: Step,
builder: *std.build.Builder,

/// Resulting binary
out_path: GeneratedFile,

/// See Options
name: []const u8,
out_name: []const u8,
input_a: FileSource,
input_b: FileSource,

pub fn create(builder: *std.build.Builder, opts: Options) *LipoStep {
    const self = builder.allocator.create(LipoStep) catch @panic("OOM");
    self.* = .{
        .step = Step.init(.custom, builder.fmt("lipo {s}", .{opts.name}), builder.allocator, make),
        .builder = builder,
        .name = opts.name,
        .out_path = .{ .step = &self.step },
        .out_name = opts.out_name,
        .input_a = opts.input_a,
        .input_b = opts.input_b,
    };
    return self;
}

fn make(step: *Step) !void {
    const self = @fieldParentPtr(LipoStep, "step", step);

    // We use a RunStep here to ease our configuration.
    const run = std.build.RunStep.create(self.builder, self.builder.fmt(
        "lipo {s}",
        .{self.name},
    ));
    run.addArgs(&.{ "lipo", "-create", "-output" });
    try run.argv.append(.{ .output = .{
        .generated_file = &self.out_path,
        .basename = self.out_name,
    } });
    run.addFileSourceArg(self.input_a);
    run.addFileSourceArg(self.input_b);
    try run.step.make();
}
