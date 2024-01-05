const std = @import("std");
const builtin = @import("builtin");

pub const Options = struct { add: ?bool = null, subtract: ?bool = null };

pub fn module(b: *std.Build, options: Options) *std.Build.Module {
    const dirname = comptime std.fs.path.dirname(@src().file) orelse ".";
    const build_options = b.addOptions();
    build_options.addOption(?bool, "add", options.add);
    build_options.addOption(?bool, "subtract", options.subtract);
    return b.createModule(.{
        .root_source_file = .{ .path = dirname ++ "/src/lib/zigpkg.zig" },
        .imports = &.{.{ .name = "zigpkg_options", .module = build_options.createModule() }},
    });
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const node_headers = b.option([]const u8, "node-headers", "Path to node headers");
    const node_import_lib =
        b.option([]const u8, "node-import-library", "Path to node import library (Windows)");
    const wasm = b.option(bool, "wasm", "Build a WASM library") orelse false;
    const wasm_stack_size =
        b.option(u64, "wasm-stack-size", "The size of WASM stack") orelse std.wasm.page_size;
    const dynamic = b.option(bool, "dynamic", "Build a dynamic library") orelse false;
    const strip = b.option(bool, "strip", "Strip debugging symbols from binary");
    const pic = b.option(bool, "pic", "Force position independent code");

    const cmd = b.findProgram(&[_][]const u8{"strip"}, &[_][]const u8{}) catch null;

    const json = @embedFile("package.json");
    var parsed = try std.json.parseFromSlice(std.json.Value, b.allocator, json, .{});
    defer parsed.deinit();
    const version = parsed.value.object.get("version").?.string;
    const description = parsed.value.object.get("description").?.string;
    var repository = std.mem.split(u8, parsed.value.object.get("repository").?.string, ":");
    std.debug.assert(std.mem.eql(u8, repository.first(), "github"));

    const add = b.option(bool, "add", "Enable add");
    const subtract = b.option(bool, "subtract", "Enable subtract");

    const options = b.addOptions();
    options.addOption(?bool, "add", add);
    options.addOption(?bool, "subtract", subtract);

    const name = "zigpkg";

    var c = false;
    if (node_headers) |headers| {
        const addon = b.fmt("{s}.node", .{name});
        const lib = b.addSharedLibrary(.{
            .name = addon,
            .root_source_file = .{ .path = "src/lib/node.zig" },
            .optimize = optimize,
            .target = target,
            .strip = strip,
            .pic = pic,
        });
        lib.root_module.addOptions("zigpkg_options", options);
        lib.addSystemIncludePath(.{ .path = headers });
        lib.linkLibC();
        if (node_import_lib) |il| {
            lib.addObjectFile(.{ .path = il });
        } else if (target.result.os.tag == .windows) {
            try std.io.getStdErr().writeAll("Must provide --node-import-library path on Windows\n");
            std.process.exit(1);
        }
        lib.linker_allow_shlib_undefined = true;
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd);
        // Always emit to build/lib because this is where the driver code expects to find it
        // TODO(ziglang/zig#2231): using the following used to work (perhaps incorrectly):
        //
        //    lib.emit_bin = .{ .emit_to = b.fmt("build/lib/{s}", .{addon}) };
        //    b.getInstallStep().dependOn(&lib.step);
        //
        // But ziglang/zig#14647 broke this so we now need to do an install() and then manually
        // rename the file ourself in install-zig-engine
        b.installArtifact(lib);
    } else if (wasm) {
        const opts = .{
            .name = name,
            .root_source_file = .{ .path = "src/lib/wasm.zig" },
            .optimize = switch (optimize) {
                .ReleaseFast, .ReleaseSafe => .ReleaseSmall,
                else => optimize,
            },
            .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
            .strip = strip,
            .pic = pic,
        };
        const lib = b.addExecutable(opts);
        lib.entry = .disabled;
        lib.stack_size = wasm_stack_size;
        lib.root_module.export_symbol_names = &[_][]const u8{ "ADD", "SUBTRACT", "compute" };
        lib.root_module.addOptions("zigpkg_options", options);
        const opt = b.findProgram(
            &[_][]const u8{"wasm-opt"},
            &[_][]const u8{"./node_modules/.bin"},
        ) catch null;
        if (optimize != .Debug and opt != null) {
            const out = b.fmt("build/lib/{s}.wasm", .{name});
            const sh = b.addSystemCommand(&[_][]const u8{ opt.?, "-O4" });
            sh.addArtifactArg(lib);
            sh.addArg("-o");
            sh.addFileArg(.{ .path = out });
            b.getInstallStep().dependOn(&sh.step);
        } else {
            b.getInstallStep().dependOn(&b.addInstallArtifact(lib, .{
                .dest_dir = .{ .override = std.Build.InstallDir{ .lib = {} } },
            }).step);
        }
    } else if (dynamic) {
        const lib = b.addSharedLibrary(.{
            .name = name,
            .root_source_file = .{ .path = "src/lib/c.zig" },
            .version = try std.SemanticVersion.parse(version),
            .optimize = optimize,
            .target = target,
            .strip = strip,
            .pic = pic,
        });
        lib.root_module.addOptions("zigpkg_options", options);
        lib.addIncludePath(.{ .path = "src/include" });
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd);
        b.installArtifact(lib);
        c = true;
    } else {
        const lib = b.addStaticLibrary(.{
            .name = name,
            .root_source_file = .{ .path = "src/lib/c.zig" },
            .optimize = optimize,
            .target = target,
            .strip = strip,
            .pic = pic,
        });
        lib.root_module.addOptions("zigpkg_options", options);
        lib.addIncludePath(.{ .path = "src/include" });
        lib.bundle_compiler_rt = true;
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd);
        b.installArtifact(lib);
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
    const test_filter = b.option([]const u8, "test-filter", "Skip tests that do not match filter");

    const tests = b.addTest(.{
        .root_source_file = .{ .path = test_file },
        .optimize = optimize,
        .target = target,
        .filter = test_filter,
        .single_threaded = true,
        .strip = strip,
        .pic = pic,
    });
    tests.root_module.addOptions("zigpkg_options", options);
    maybeStrip(b, tests, &tests.step, strip, cmd);
    if (coverage) |path| {
        tests.setExecCmd(&.{ "kcov", "--include-pattern=src/lib", path, null });
    }

    b.step("test", "Run all tests").dependOn(&b.addRunArtifact(tests).step);
}

fn maybeStrip(
    b: *std.Build,
    artifact: *std.Build.Step.Compile,
    step: *std.Build.Step,
    strip: ?bool,
    cmd: ?[]const u8,
) void {
    if (!(strip orelse false) or cmd == null) return;
    // Using `strip -r -u` for dynamic libraries is supposed to work on macOS but doesn't...
    const mac = builtin.os.tag == .macos;
    if (mac and artifact.isDynamicLibrary()) return;
    // Assuming GNU strip, which complains "illegal pathname found in archive member"...
    if (!mac and artifact.isStaticLibrary()) return;
    const sh = b.addSystemCommand(&[_][]const u8{ cmd.?, if (mac) "-x" else "-s" });
    sh.addArtifactArg(artifact);
    step.dependOn(&sh.step);
}
