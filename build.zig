const std = @import("std");
const builtin = @import("builtin");

pub fn module(b: *std.Build, build_options: *std.Build.Module) *std.Build.Module {
    const dirname = comptime std.fs.path.dirname(@src().file) orelse ".";
    return b.createModule(.{
        .source_file = .{ .path = dirname ++ "/src/lib/zigpkg.zig" },
        .dependencies = &.{.{ .name = "build_options", .module = build_options }},
    });
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var parser = std.json.Parser.init(b.allocator, false);
    defer parser.deinit();
    var tree = try parser.parse(@embedFile("package.json"));
    defer tree.deinit();
    const version = tree.root.Object.get("version").?.String;

    const foo = b.option(bool, "foo", "Enable foo") orelse false;
    const bar = b.option(bool, "bar", "Enable bar") orelse false;
    const dynamic = b.option(bool, "dynamic", "Build a dynamic library") orelse false;
    const strip = b.option(bool, "strip", "Strip debugging symbols from binary") orelse false;
    const pic = b.option(bool, "pic", "Force position independent code") orelse false;

    const cmd = b.findProgram(&[_][]const u8{"strip"}, &[_][]const u8{}) catch null;

    const options = b.addOptions();
    options.addOption(bool, "foo", foo);
    options.addOption(bool, "bar", bar);

    const lib = if (foo) "zigpkg-foo" else "zigpkg";

    const node_headers = b.option([]const u8, "node-headers", "Path to node headers");
    const node_import_lib =
        b.option([]const u8, "node-import-library", "Path to node import library (Windows)");
    if (node_headers) |headers| {
        const name = b.fmt("{s}.node", .{lib});
        const node_lib = b.addSharedLibrary(.{
            .name = name,
            .root_source_file = .{ .path = "src/lib/binding/node.zig" },
            .optimize = optimize,
            .target = target,
        });
        node_lib.addOptions("build_options", options);
        node_lib.setMainPkgPath("./");
        node_lib.addSystemIncludePath(headers);
        node_lib.linkLibC();
        if (node_import_lib) |il| {
            if (std.fs.path.dirname(il)) |dir| node_lib.addLibraryPath(dir);
            node_lib.linkSystemLibraryName(std.fs.path.basename(il));
        } else if (target.os.tag == .windows ) {
            std.debug.print("Must provide --node-import-library path on Windows");
            std.process.exit(1);
        }
        node_lib.linker_allow_shlib_undefined = true;
        const out = b.fmt("build/lib/{s}", .{name});
        maybeStrip(b, node_lib, b.getInstallStep(), strip, cmd, out);
        if (pic) node_lib.force_pic = pic;
        node_lib.emit_bin = .{ .emit_to = out };
        b.getInstallStep().dependOn(&node_lib.step);
    } else if (dynamic) {
        const dynamic_lib = b.addSharedLibrary(.{
            .name = lib,
            .root_source_file = .{ .path = "src/lib/binding/c.zig" },
            .version = try std.builtin.Version.parse(version),
            .optimize = optimize,
            .target = target,
        });
        dynamic_lib.addOptions("build_options", options);
        dynamic_lib.setMainPkgPath("./");
        dynamic_lib.addIncludePath("src/include");
        maybeStrip(b, dynamic_lib, b.getInstallStep(), strip, cmd, null);
        if (pic) dynamic_lib.force_pic = pic;
        dynamic_lib.install();
    } else {
        const static_lib = b.addStaticLibrary(.{
            .name = lib,
            .root_source_file = .{ .path = "src/lib/binding/c.zig" },
            .optimize = optimize,
            .target = target,
        });
        static_lib.addOptions("build_options", options);
        static_lib.setMainPkgPath("./");
        static_lib.addIncludePath("src/include");
        static_lib.bundle_compiler_rt = true;
        maybeStrip(b, static_lib, b.getInstallStep(), strip, cmd, null);
        if (pic) static_lib.force_pic = pic;
        static_lib.install();
    }

    if (node_headers == null) {
        const header = b.addInstallFileWithDir(
            .{ .path = "src/include/zigpkg.h" },
            .header,
            "zigpkg.h",
        );
        b.getInstallStep().dependOn(&header.step);
    }
    {
        const pc = b.fmt("lib{s}.pc", .{lib});
        const file = try b.cache_root.join(b.allocator, &.{pc});
        const pkgconfig_file = try std.fs.cwd().createFile(file, .{});

        const dirname = comptime std.fs.path.dirname(@src().file) orelse ".";
        const suffix = if (foo) "-foo" else "";
        const writer = pkgconfig_file.writer();
        try writer.print(
            \\prefix={0s}/{1s}
            \\includedir=${{prefix}}/include
            \\libdir=${{prefix}}/lib
            \\
            \\Name: lib{2s}
            \\URL: https://github.com/scheibo/zigpkg
            \\Description: zigpkg{3s} library
            \\Version: {4s}
            \\Cflags: -I${{includedir}}
            \\Libs: -L${{libdir}} -l{2s}
        , .{ dirname, b.install_path, lib, suffix, version });
        defer pkgconfig_file.close();

        b.installFile(file, b.fmt("share/pkgconfig/{s}", .{pc}));
    }

    const coverage = b.option([]const u8, "test-coverage", "Generate test coverage");
    const test_file =
        b.option([]const u8, "test-file", "Input file for test") orelse "src/lib/test.zig";
    const test_bin = b.option([]const u8, "test-bin", "Emit test binary to");
    const test_filter = b.option([]const u8, "test-filter", "Skip tests that do not match filter");
    const test_no_exec =
        b.option(bool, "test-no-exec", "Compiles test binary without running it") orelse false;

    const tests = b.addTest(.{
        .root_source_file = .{ .path = test_file },
        .kind = if (test_no_exec) .test_exe else .@"test",
        .optimize = optimize,
        .target = target,
    });
    tests.setMainPkgPath("./");
    tests.setFilter(test_filter);
    tests.addOptions("build_options", options);
    tests.single_threaded = true;
    maybeStrip(b, tests, &tests.step, strip, cmd, null);
    if (pic) tests.force_pic = pic;
    if (test_bin) |bin| {
        tests.name = std.fs.path.basename(bin);
        if (std.fs.path.dirname(bin)) |dir| tests.setOutputDir(dir);
    }
    if (coverage) |path| {
        tests.setExecCmd(&.{ "kcov", "--include-pattern=src/lib", path, null });
    }

    const format = b.addFmt(&.{"."});

    b.step("format", "Format source files").dependOn(&format.step);
    b.step("test", "Run all tests").dependOn(&tests.step);
}

fn maybeStrip(
    b: *std.Build,
    artifact: *std.Build.CompileStep,
    step: *std.Build.Step,
    strip: bool,
    cmd: ?[]const u8,
    out: ?[]const u8,
) void {
    artifact.strip = strip;
    if (!strip or cmd == null) return;
    // Using `strip -r -u` for dynamic libraries is supposed to work on macOS but doesn't...
    const mac = builtin.os.tag == .macos;
    if (mac and artifact.isDynamicLibrary()) return;
    // Assuming GNU strip, which complains "illegal pathname found in archive member"...
    if (!mac and artifact.isStaticLibrary()) return;
    const sh = b.addSystemCommand(&[_][]const u8{ cmd.?, if (mac) "-x" else "-s" });
    if (out) |path| {
        sh.addArg(path);
        sh.step.dependOn(&artifact.step);
    } else {
        sh.addArtifactArg(artifact);
    }
    step.dependOn(&sh.step);
}
