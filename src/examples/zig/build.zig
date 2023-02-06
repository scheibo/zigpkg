const std = @import("std");
const zigpkg = @import("lib/zigpkg/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const foo = b.option(bool, "foo", "Enable foo") orelse false;
    const bar = b.option(bool, "bar", "Enable bar") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "foo", foo);
    options.addOption(bool, "bar", bar);

    const exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = .{ .path = "example.zig" },
        .optimize = optimize,
        .target = target,
    });
    exe.addModule("zigpkg", zigpkg.module(b, options.createModule()));
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
