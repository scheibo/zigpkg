const std = @import("std");
const builtin = @import("builtin");

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

    const cmd = if (@hasDecl(std.Build, "FindProgramOptions"))
        b.findProgram(.{ .names = &.{"strip"} })
    else
        b.findProgram(&[_][]const u8{"strip"}, &[_][]const u8{}) catch null;

    const json = @embedFile("package.json");
    var parsed = try std.json.parseFromSlice(std.json.Value, b.allocator, json, .{});
    defer parsed.deinit();
    const version = parsed.value.object.get("version").?.string;
    const description = parsed.value.object.get("description").?.string;
    var repository = std.mem.splitSequence(u8, parsed.value.object.get("repository").?.string, ":");
    std.debug.assert(std.mem.eql(u8, repository.first(), "github"));

    const add = b.option(bool, "add", "Enable add");
    const subtract = b.option(bool, "subtract", "Enable subtract");

    const options = b.addOptions();
    options.addOption(?bool, "add", add);
    options.addOption(?bool, "subtract", subtract);

    const name = "zigpkg";
    _ = b.addModule(name, .{
        .root_source_file = b.path("src/lib/zigpkg.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{.{ .name = "zigpkg_options", .module = options.createModule() }},
    });

    var c = false;
    if (node_headers) |headers| {
        const translate_c = b.addTranslateC(.{
            .root_source_file = b.path("src/lib/napi.h"),
            .target = target,
            .optimize = optimize,
        });
        translate_c.addSystemIncludePath(b.path(headers));
        const addon = b.fmt("{s}.node", .{name});
        const lib = b.addLibrary(.{
            .linkage = .dynamic,
            .name = addon,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/lib/node.zig"),
                .optimize = optimize,
                .target = target,
                .strip = strip,
                .pic = pic,
            }),
        });
        lib.root_module.addOptions("zigpkg_options", options);
        lib.root_module.addImport("napi", translate_c.createModule());
        lib.root_module.link_libc = true;
        if (node_import_lib) |il| {
            lib.root_module.addObjectFile(b.path(il));
        } else if (target.result.os.tag == .windows) {
            const msg = "Must provide --node-import-library path on Windows\n";
            var writer = std.Io.File.stderr().writer(b.graph.io, &.{});
            try writer.interface.writeAll(msg);
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
        const opts: std.Build.ExecutableOptions = .{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/lib/wasm.zig"),
                .optimize = switch (optimize) {
                    .ReleaseFast, .ReleaseSafe => .ReleaseSmall,
                    else => optimize,
                },
                .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
                .strip = strip,
                .pic = pic,
            }),
        };
        const lib = b.addExecutable(opts);
        lib.entry = .disabled;
        lib.stack_size = wasm_stack_size;
        lib.root_module.export_symbol_names = &[_][]const u8{ "ADD", "SUBTRACT", "compute" };
        lib.root_module.addOptions("zigpkg_options", options);
        const opt = if (@hasDecl(std.Build, "FindProgramOptions")) blk: {
            if (exists(b, "./node_modules/.bin/wasm-opt") catch false) {
                break :blk "./node_modules/.bin/wasm-opt";
            }
            break :blk b.findProgram(.{ .names = &.{"wasm-opt"} });
        } else b.findProgram(
            &[_][]const u8{"wasm-opt"},
            &[_][]const u8{"./node_modules/.bin"},
        ) catch null;
        if (optimize != .Debug and opt != null) {
            const out = b.fmt("build/lib/{s}.wasm", .{name});
            const sh = b.addSystemCommand(&[_][]const u8{ opt.?, "-O4" });
            sh.addArtifactArg(lib);
            sh.addArg("-o");
            sh.addFileArg(b.path(out));
            b.getInstallStep().dependOn(&sh.step);
        } else {
            b.getInstallStep().dependOn(&b.addInstallArtifact(lib, .{
                .dest_dir = .{ .override = std.Build.InstallDir{ .lib = {} } },
            }).step);
        }
    } else if (dynamic) {
        const lib = b.addLibrary(.{
            .linkage = .dynamic,
            .version = try std.SemanticVersion.parse(version),
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/lib/c.zig"),
                .optimize = optimize,
                .target = target,
                .strip = strip,
                .pic = pic,
            }),
        });
        lib.root_module.addOptions("zigpkg_options", options);
        lib.root_module.addIncludePath(b.path("src/include"));
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd);
        b.installArtifact(lib);
        c = true;
    } else {
        const lib = b.addLibrary(.{
            .linkage = .static,
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/lib/c.zig"),
                .optimize = optimize,
                .target = target,
                .strip = strip,
                .pic = pic,
            }),
        });
        lib.root_module.addOptions("zigpkg_options", options);
        lib.root_module.addIncludePath(b.path("src/include"));
        if (target.result.os.tag != .macos) {
            lib.bundle_compiler_rt = true;
        }
        maybeStrip(b, lib, b.getInstallStep(), strip, cmd);
        const install = b.addInstallArtifact(lib, .{});
        b.getInstallStep().dependOn(&install.step);
        maybeRanlib(b, lib, &install.step);
        c = true;
    }

    if (c) {
        const header = b.addInstallFileWithDir(
            b.path("src/include/zigpkg.h"),
            .header,
            "zigpkg.h",
        );
        b.getInstallStep().dependOn(&header.step);

        const content = try std.fmt.allocPrint(b.allocator,
            \\prefix=${{pcfiledir}}/../..
            \\includedir=${{prefix}}/include
            \\libdir=${{prefix}}/lib
            \\
            \\Name: lib{0s}
            \\URL: https://github.com/{1s}
            \\Description: {2s}
            \\Version: {3s}
            \\Cflags: -I${{includedir}}
            \\Libs: -L${{libdir}} -l{0s}
        , .{ name, repository.next().?, description, version });

        const pc = b.fmt("lib{s}.pc", .{name});
        if (@hasDecl(std.Build, "FindProgramOptions")) {
            const write_file = b.addWriteFiles();
            const pkgconfig = write_file.add(pc, content);
            b.getInstallStep().dependOn(&b.addInstallFileWithDir(
                pkgconfig,
                .prefix,
                b.fmt("share/pkgconfig/{s}", .{pc}),
            ).step);
        } else {
            const cwd = try std.process.currentPathAlloc(b.graph.io, b.allocator);
            const file = try std.Io.Dir.path.relative(
                b.allocator,
                cwd,
                &b.graph.environ_map,
                cwd,
                try b.cache_root.join(b.allocator, &.{pc}),
            );
            const pkgconfig_file = try std.Io.Dir.cwd().createFile(b.graph.io, file, .{});
            defer pkgconfig_file.close(b.graph.io);

            var writer = pkgconfig_file.writer(b.graph.io, &.{});
            try writer.interface.writeAll(content);

            b.installFile(file, b.fmt("share/pkgconfig/{s}", .{pc}));
        }
    }

    const coverage = b.option([]const u8, "test-coverage", "Generate test coverage");
    const test_file =
        b.option([]const u8, "test-file", "Input file for test") orelse "src/lib/test.zig";
    const test_filter = b.option([]const u8, "test-filter", "Skip tests that do not match filter");

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(test_file),
            .optimize = optimize,
            .target = target,
            .single_threaded = true,
            .strip = strip,
            .pic = pic,
        }),
        .filters = if (test_filter) |filter| &.{filter} else &.{},
    });
    tests.root_module.addOptions("zigpkg_options", options);
    maybeStrip(b, tests, &tests.step, strip, cmd);
    const run_tests = b.addRunArtifact(tests);
    if (coverage) |path| {
        const kcov_run = b.addSystemCommand(&.{ "kcov", "--include-pattern=src/lib", path });
        kcov_run.addArtifactArg(tests);
        kcov_run.enableTestRunnerMode();
        b.step("test", "Run all tests").dependOn(&kcov_run.step);
    } else {
        b.step("test", "Run all tests").dependOn(&run_tests.step);
    }
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

fn maybeRanlib(
    b: *std.Build,
    artifact: *std.Build.Step.Compile,
    install_step: *std.Build.Step,
) void {
    if (builtin.os.tag != .macos) return;
    if (artifact.linkage != .static) return;

    const ranlib = if (comptime @hasDecl(std.Build, "FindProgramOptions"))
        b.findProgram(.{ .names = &.{"ranlib"} }) orelse return
    else
        b.findProgram(&[_][]const u8{"ranlib"}, &[_][]const u8{}) catch return;

    const sh = b.addSystemCommand(&[_][]const u8{ranlib});
    sh.addFileArg(artifact.getEmittedBin());
    install_step.dependOn(&sh.step);
}

fn exists(b: *std.Build, path: []const u8) !bool {
    if (comptime @hasDecl(std, "Io")) {
        std.Io.Dir.cwd().access(b.graph.io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => |e| return e,
        };
    } else {
        std.fs.cwd().access(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => |e| return e,
        };
    }
    return true;
}
