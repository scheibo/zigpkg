const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const add = b.option(bool, "add", "Enable addition") orelse false;
    const subtract = b.option(bool, "subtract", "Enable subtraction") orelse false;

    const exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("example.zig"),
        .optimize = optimize,
        .target = target,
    });
    const zigpkg = b.dependency("zigpkg", .{ .add = add, .subtract = subtract });
    exe.root_module.addImport("zigpkg", zigpkg.module("zigpkg"));
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
