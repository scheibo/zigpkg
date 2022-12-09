const std = @import("std");
const zigpkg = @import("lib/zigpkg/build.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const foo = b.option(bool, "foo", "Enable foo") orelse false;
    const bar = b.option(bool, "bar", "Enable bar") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "foo", foo);
    options.addOption(bool, "bar", bar);

    const build_options = options.getPackage("build_options");

    const exe = b.addExecutable("zig", "example.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackage(zigpkg.pkg(b, build_options));
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
