const std = @import("std");

const Builder = std.build.Builder;
const Pkg = std.build.Pkg;

pub fn pkg(b: *Builder, build_options: Pkg) Pkg {
    const dirname = comptime std.fs.path.dirname(@src().file) orelse ".";
    const source = .{ .path = dirname ++ "/src/lib/zigpkg.zig" };
    const package = if (@hasField(Pkg, "path"))
        Pkg{ .name = "zigpkg", .path = source, .dependencies = &.{build_options} }
    else
        Pkg{ .name = "zigpkg", .source = source, .dependencies = &.{build_options} };
    return b.dupePkg(package);
}

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

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

    const static_lib = b.addStaticLibrary(lib, "src/lib/binding/c.zig");
    static_lib.addOptions("build_options", options);
    static_lib.setBuildMode(mode);
    static_lib.setTarget(target);
    if (@hasDecl(std.build.LibExeObjStep, "addIncludePath")) {
        static_lib.addIncludePath("src/include");
    } else {
        static_lib.addIncludeDir("src/include");
    }
    static_lib.strip = strip;
    static_lib.install();

    const versioned = .{ .versioned = try std.builtin.Version.parse(version) };
    const dynamic_lib = b.addSharedLibrary(lib, "src/lib/binding/c.zig", versioned);
    dynamic_lib.addOptions("build_options", options);
    dynamic_lib.setBuildMode(mode);
    dynamic_lib.setTarget(target);
    if (@hasDecl(std.build.LibExeObjStep, "addIncludePath")) {
        dynamic_lib.addIncludePath("src/include");
    } else {
        dynamic_lib.addIncludeDir("src/include");
    }
    dynamic_lib.strip = strip;
    dynamic_lib.install();

    const node_headers = b.option([]const u8, "node-headers", "Path to node-headers");
    if (node_headers) |headers| {
        const name = b.fmt("{s}.node", .{lib});
        const node_lib = b.addSharedLibrary(name, "src/lib/binding/node.zig", .unversioned);
        if (@hasDecl(std.build.LibExeObjStep, "addSystemIncludePath")) {
            node_lib.addSystemIncludePath(headers);
        } else {
            node_lib.addSystemIncludeDir(headers);
        }
        node_lib.addOptions("build_options", options);
        node_lib.setBuildMode(mode);
        node_lib.setTarget(target);
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

        const suffix = if (foo) "-foo" else "";
        const writer = pkgconfig_file.writer();
        try writer.print(
            \\prefix={0s}
            \\includedir=${{prefix}}/include
            \\libdir=${{prefix}}/lib
            \\
            \\Name: lib{1s}
            \\URL: https://github.com/zigpkg/engine
            \\Description: zigpkg{2s} library.
            \\Version: {3s}
            \\Cflags: -I${{includedir}}
            \\Libs: -L${{libdir}} -l{1s}
        , .{ b.install_prefix, lib, suffix, version });
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

    const tests = if (test_no_exec) b.addTestExe("test_exe", test_file) else b.addTest(test_file);
    tests.setMainPkgPath("./");
    tests.setFilter(test_filter);
    tests.addOptions("build_options", options);
    tests.setBuildMode(mode);
    tests.setTarget(target);
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
