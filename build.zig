const std = @import("std");
const builtin = @import("builtin");

const NativeTargetInfo = std.zig.system.NativeTargetInfo;

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

    const node_headers = b.option([]const u8, "node-headers", "Path to node headers");
    const node_import_lib =
        b.option([]const u8, "node-import-library", "Path to node import library (Windows)");
    const wasm = b.option(bool, "wasm", "Build a WASM library") orelse false;
    const dynamic = b.option(bool, "dynamic", "Build a dynamic library") orelse false;
    const strip = b.option(bool, "strip", "Strip debugging symbols from binary") orelse false;
    const pic = b.option(bool, "pic", "Force position independent code") orelse false;

    const cmd = b.findProgram(&[_][]const u8{"strip"}, &[_][]const u8{}) catch null;

    var parser = std.json.Parser.init(b.allocator, false);
    defer parser.deinit();
    var tree = try parser.parse(@embedFile("package.json"));
    defer tree.deinit();
    const version = tree.root.Object.get("version").?.String;
    const description = tree.root.Object.get("description").?.String;
    var repository = std.mem.split(u8, tree.root.Object.get("repository").?.String, ":");
    std.debug.assert(std.mem.eql(u8, repository.first(), "github"));

    const add = b.option(bool, "add", "Enable add") orelse false;
    const subtract = b.option(bool, "subtract", "Enable subtract") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "add", add);
    options.addOption(bool, "subtract", subtract);

    const name = "zigpkg";

    var c = false;
    if (node_headers) |headers| {
        const addon = b.fmt("{s}.node", .{name});
        const lib = b.addSharedLibrary(.{
            .name = addon,
            .root_source_file = .{ .path = "src/lib/binding/node.zig" },
            .optimize = optimize,
            .target = target,
        });
        lib.addOptions("build_options", options);
        lib.setMainPkgPath("./");
        lib.addSystemIncludePath(headers);
        lib.linkLibC();
        if (node_import_lib) |il| {
            lib.addObjectFile(il);
        } else if ((try NativeTargetInfo.detect(target)).target.os.tag == .windows) {
            std.debug.print("Must provide --node-import-library path on Windows", .{});
            std.process.exit(1);
        }
        lib.linker_allow_shlib_undefined = true;
        const out = b.fmt("build/lib/{s}", .{addon});
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd, out);
        if (pic) lib.force_pic = pic;
        // Always emit to build/lib because this is where the driver code expects to find it
        // TODO: switch to whatever ziglang/zig#2231 comes up with
        lib.emit_bin = .{ .emit_to = out };
        b.getInstallStep().dependOn(&lib.step);
    } else if (wasm) {
        const lib = b.addSharedLibrary(.{
            .name = name,
            .root_source_file = .{ .path = "src/lib/binding/wasm.zig" },
            .optimize = switch (optimize) {
                .ReleaseFast, .ReleaseSafe => .ReleaseSmall,
                else => optimize,
            },
            .target = .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
        });
        lib.addOptions("build_options", options);
        lib.setMainPkgPath("./");
        lib.rdynamic = true;
        lib.strip = strip;
        if (pic) lib.force_pic = pic;
        const opt = b.findProgram(
            &[_][]const u8{"wasm-opt"},
            &[_][]const u8{"./node_modules/.bin"},
        ) catch null;
        if (optimize != .Debug and opt != null) {
            const out = b.fmt("build/lib/{s}.wasm", .{name});
            const sh = b.addSystemCommand(&[_][]const u8{ opt.?, "-O4" });
            sh.addArtifactArg(lib);
            sh.addArg("-o");
            sh.addFileSourceArg(.{ .path = out });
            b.getInstallStep().dependOn(&sh.step);
        }
        lib.install();
    } else if (dynamic) {
        const lib = b.addSharedLibrary(.{
            .name = name,
            .root_source_file = .{ .path = "src/lib/binding/c.zig" },
            .version = try std.builtin.Version.parse(version),
            .optimize = optimize,
            .target = target,
        });
        lib.addOptions("build_options", options);
        lib.setMainPkgPath("./");
        lib.addIncludePath("src/include");
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd, null);
        if (pic) lib.force_pic = pic;
        lib.install();
        c = true;
    } else {
        const lib = b.addStaticLibrary(.{
            .name = name,
            .root_source_file = .{ .path = "src/lib/binding/c.zig" },
            .optimize = optimize,
            .target = target,
        });
        lib.addOptions("build_options", options);
        lib.setMainPkgPath("./");
        lib.addIncludePath("src/include");
        lib.bundle_compiler_rt = true;
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd, null);
        if (pic) lib.force_pic = pic;
        lib.install();
        c = true;
    }

    if (c) {
        const header = b.addInstallFileWithDir(
            .{ .path = "src/include/zigpkg.h" },
            .header,
            "zigpkg.h",
        );
        b.getInstallStep().dependOn(&header.step);

        const pc = b.fmt("lib{s}.pc", .{name});
        const file = try b.cache_root.join(b.allocator, &.{pc});
        const pkgconfig_file = try std.fs.cwd().createFile(file, .{});

        const dirname = comptime std.fs.path.dirname(@src().file) orelse ".";
        const writer = pkgconfig_file.writer();
        try writer.print(
            \\prefix={0s}/{1s}
            \\includedir=${{prefix}}/include
            \\libdir=${{prefix}}/lib
            \\
            \\Name: lib{2s}
            \\URL: https://github.com/{3s}
            \\Description: {4s}
            \\Version: {5s}
            \\Cflags: -I${{includedir}}
            \\Libs: -L${{libdir}} -l{2s}
        , .{ dirname, b.install_path, name, repository.next().?, description, version });
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
