const std = @import("std");

const Pkg = std.Build.Pkg;

pub fn pkg(b: *std.Build, build_options: Pkg) Pkg {
    const dirname = comptime std.fs.path.dirname(@src().file) orelse ".";
    const source = .{ .path = dirname ++ "/src/lib/zigpkg.zig" };
    return b.dupePkg(Pkg{ .name = "zigpkg", .source = source, .dependencies = &.{build_options} });
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
    const strip = b.option(bool, "strip", "Strip debugging symbols from binary") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "foo", foo);
    options.addOption(bool, "bar", bar);

    const lib = if (foo) "zigpkg-foo" else "zigpkg";

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
    static_lib.strip = strip;
    static_lib.install();

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
    dynamic_lib.strip = strip;
    dynamic_lib.install();

    const node_headers = b.option([]const u8, "node-headers", "Path to node-headers");
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
        node_lib.linker_allow_shlib_undefined = true;
        node_lib.strip = strip;
        node_lib.emit_bin = .{ .emit_to = b.fmt("build/lib/{s}", .{name}) };
        b.getInstallStep().dependOn(&node_lib.step);
    }

    const header = b.addInstallFileWithDir(
        .{ .path = "src/include/zigpkg.h" },
        .header,
        "zigpkg.h",
    );
    b.getInstallStep().dependOn(&header.step);
    {
        const pc = b.fmt("lib{s}.pc", .{lib});

        const file = try std.fs.path.join(
            b.allocator,
            &.{ b.cache_root, pc },
        );
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
    tests.strip = strip;
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
