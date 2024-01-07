**zigpkg** is intended to be a minimal reproduction/playground of the build configuration most of my
projects use that I've been maintaining to make it easier for myself to separate out the complexity
inherent in what I'm trying to do vs. the specifics of an individual project. The requirements:

- produce a Zig module/package/library easily consumable by other Zig projects
- produce static and dynamic libraries which can be consumed by any language that can interface with
  a C API
- produce a NodeJS addon
- produce a WASM binding that works in the browser (not 100% done this part - though loading the
  WASM works in NodeJS)

And then finally, demonstrate using build options to be able to change the behavior of the resulting
artifacts at compile time.

---

Going through the [`build.zig`](build.zig):

```zig
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
```

Mostly uninteresting stuff - by default we're going to produce a static library but we allow for
opting-in to a dynamic library/NodeJS/WASM. The explicit WASM stack size is not really required for
this example project but is a requirement for the projects this example was extracted from. The one
ugliness here is the need to search for `strip` (and the `maybeStrip` code that uses it - though the
complexity in that function is mainly to work around the differences in system-installed `strip`
binaries and not related to Zig) - as a user, I would expect this would already be handled by
`.strip = true`. However, if you compare the size of the library with and without the external
`strip`:

```sh
$ zig build -p build -Doptimize=ReleaseFast -Dstrip
$ wc -c build/lib/libzigpkg.a
  157680 build/lib/libzigpkg.a

# comment out maybeStrip, just use Zig's .strip
$ zig build -p build -Doptimize=ReleaseFast -Dstrip
$ wc -c build/lib/libzigpkg.a
  159808 build/lib/libzigpkg.a
```

Back to the rest of the build:

```zig
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
```

No real complaints here, this seems fine - extracting some info from another file and setting up
build options. The next bit  where we actually start building artifacts is more interesting:

```zig
    if (node_headers) |headers| {
        const addon = b.fmt("{s}.node", .{name});
        const lib = b.addSharedLibrary(.{
            .name = addon,
            .root_source_file = .{ .path = "src/lib/binding/node.zig" },
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
```

Previously I used `(try NativeTargetInfo.detect(target)).target.os.tag == .windows` to detect
Windows but I think `target.result.os.tag == .windows` works? I'm not entirely sure - it seems to
work and also seems a lot simpler than before, but I don't know if this is the blessed way to
figured out "hey, is this artifact being build for windows?". 

Similarly, `lib.addOptions` used to work and now I need to instead call it on `root_module`?
Literally everything with `root_module` seems like some complication I shouldn't need to care or
know about - I'd bet a non trivial fraction of projects are *only* going to have a root module and
nothing else, so forcing everyone to need to learn about it seems excessive? Perhaps this is a
consequence of Zig's build system needing to support C/C++ and so Zig-specific stuff got shunted
into the `root_module` which I guess makes sense, but it seems to regress the experience of Zig
users which are also likely to be the main users?

Needing to know about `linker_allow_shlib_undefined` to be able to build the NodeJS addon was a
hurdle - not sure how to make that any simpler though, I'm not sure this is Zig's "fault".

The annoying thing that *does* seem to be on Zig is that there doesn't seem to be a good way to just
change the resulting artifacts name - NodeJS addons need to be suffixed with `.node`.
[#2331](https://github.com/ziglang/zig/issues/2231) is already filed for this, and originally I had
a very hacky workaround using `.emit_to` that I didn't like because it hardcoded the prefix (and
really this shouldn't be a rename step, there should be an option to allow for the file to be named
correctly to begin with), but that broke so now I've given up and [rename it in a postinstall
script](https://github.com/scheibo/zigpkg/blob/main/src/bin/install-zigpkg#L350-L355). There's
probably a cleaner way to do this rename within the build system already but I punted with the
expectation that [#2331](https://github.com/ziglang/zig/issues/2231) will just fix this eventually.

```zig
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
```

I am least confident in whatever the heck is going on with WASM - things seemed simple enough when I
just set `rdynamic` and passed in the right target, but now I need to create an executable(?) and
with "disabled entry"(?) and explicitly list every symbol name(?), whereas in past versions of Zig
all the stuff stuff `exported`-ed in the root source file was accessible. UX-wise things definitely
took a hit here for my specific usecase, and I'm really not looking forward to having to maintain a
list of the exported symbols for a non-toy project. Would love to see some sugar/changes here. It's
also very unclear to me why `entry`/`stack_size` don't get passed to the executable options (but
`strip` and `pic` now do?), and `root_module` shows up again for whatever reason - maybe all these
different places to set things makes complete sense to someone with a coherent mental model for how
the system works, but to someone just trying to spend as little time as possible dealing with build
woes needing to guess which of the 3 possible places things can be set is awkward (probably would
have been less painful had I made these changes after ZLS had been updated to be able to get some
autocomplete).

Similarly to `strip`, it would be nice if Zig could just cover the functionality `wasm-opt` provides
(and I don't even know if on this particular project it does anything given how trivial an example
it is, but on more complex projects that actually do things it seemed to make a noticable
difference). I am once again unsure how to properly respect the user's build prefix and instead just
hardcode one, though I suspect there probably *is* a way to do this and I'm just being dumb/lazy.

```zig
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
```

This is actually pretty pleasant. I forget why I need `bundle_compiler_rt` (if I were more clever I
would have added a comment). The rest of the build file is similarly boring - installing a header
and package thing (possibly lifted from
[`libflightplan`](https://github.com/mitchellh/libflightplan/blob/main/build.zig#L105-L135)?). 

The one thing I haven't touched on is the `module` function at the very begining of the build file:

```zig
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
```

I think this pattern maybe came from `zig-gamedev` or something, and predates the Zig package
manager, but I've retained it because I can't figure out how to make `b.dependency` actually work?
In the [Zig example `build.zig`]() I am currently doing the following:

```zig
const std = @import("std");
const zigpkg = @import("zigpkg");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const add = b.option(bool, "add", "Enable addition");
    const subtract = b.option(bool, "subtract", "Enable subtraction");

    const exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = .{ .path = "example.zig" },
        .optimize = optimize,
        .target = target,
    });
    exe.root_module.addImport("zigpkg", zigpkg.module(b, .{
        .add = add,
        .subtract = subtract,
    }));
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
```

Which works, whereas if I instead change it to what I feel is the "correct" way to do things:

```diff
@@ -1,5 +1,4 @@
 const std = @import("std");
-const zigpkg = @import("zigpkg");
 
 pub fn build(b: *std.Build) void {
     const target = b.standardTargetOptions(.{});
@@ -14,10 +13,13 @@ pub fn build(b: *std.Build) void {
         .optimize = optimize,
         .target = target,
     });
-    exe.root_module.addImport("zigpkg", zigpkg.module(b, .{
+    const zigpkg = b.dependency("zigpkg", .{ # 1
+        .optimize = optimize,
+        .target = target,
         .add = add,
         .subtract = subtract,
-    }));
+    });
+    exe.root_module.addImport("zigpkg", zigpkg.module("zigpkg")); # 2 + 3
     b.installArtifact(exe);
 
     const run_cmd = b.addRunArtifact(exe);
```

It first complains about the optionals:

```sh
$ make zig-example
cd examples/zig; zig build --summary all -Dadd run -- 40
/Users/kjs/Code/src/github.com/scheibo/zigpkg/examples/zig
/Users/kjs/Code/src/github.com/scheibo/zig/build/zig-macos-aarch64-0.12.0-dev.2036+fc79b22a9/lib/std/Build.zig:441:25: error: option 'add' has unsupported type: ?bool
                else => @compileError("option '" ++ field.name ++ "' has unsupported type: " ++ @typeName(T)),
                        ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
referenced by:
    dependencyInner__anon_14289: /Users/kjs/Code/src/github.com/scheibo/zig/build/zig-macos-aarch64-0.12.0-dev.2036+fc79b22a9/lib/std/Build.zig:1812:56
    dependency__anon_12993: /Users/kjs/Code/src/github.com/scheibo/zig/build/zig-macos-aarch64-0.12.0-dev.2036+fc79b22a9/lib/std/Build.zig:1731:35
    remaining reference traces hidden; use '-freference-trace' to see all reference traces
```

And then if I add defaults (`orelse false`) which isn't actually what I want, it fails claiming it
can't find the module?

```sh
$ make zig-example
cd examples/zig; zig build --summary all -Dadd run -- 40
/Users/kjs/Code/src/github.com/scheibo/zigpkg/examples/zig
thread 13517870 panic: unable to find module 'zigpkg'
/Users/kjs/Code/src/github.com/scheibo/zig/build/zig-macos-aarch64-0.12.0-dev.2036+fc79b22a9/lib/std/debug.zig:373:22: 0x102f488db in panicExtra__anon_15533 (build)
    std.builtin.panic(msg, trace, ret_addr);
                     ^
/Users/kjs/Code/src/github.com/scheibo/zig/build/zig-macos-aarch64-0.12.0-dev.2036+fc79b22a9/lib/std/debug.zig:348:15: 0x102f0468b in panic__anon_14290 (build)
    panicExtra(null, null, format, args);
              ^
/Users/kjs/Code/src/github.com/scheibo/zig/build/zig-macos-aarch64-0.12.0-dev.2036+fc79b22a9/lib/std/Build.zig:1702:18: 0x102edc577 in module (build)
            panic("unable to find module '{s}'", .{name});
                 ^
/Users/kjs/Code/src/github.com/scheibo/zigpkg/examples/zig/build.zig:22:54: 0x102e9f607 in build (build)
    exe.root_module.addImport("zigpkg", zigpkg.module("zigpkg"));
                                                     ^
/Users/kjs/Code/src/github.com/scheibo/zig/build/zig-macos-aarch64-0.12.0-dev.2036+fc79b22a9/lib/std/Build.zig:1850:33: 0x102e8c17f in runBuild__anon_7601 (build)
        .Void => build_zig.build(b),
                                ^
/Users/kjs/Code/src/github.com/scheibo/zig/build/zig-macos-aarch64-0.12.0-dev.2036+fc79b22a9/lib/build_runner.zig:319:29: 0x102e875e3 in main (build)
        try builder.runBuild(root);
                            ^
/Users/kjs/Code/src/github.com/scheibo/zig/build/zig-macos-aarch64-0.12.0-dev.2036+fc79b22a9/lib/std/start.zig:585:37: 0x102e8c5b7 in main (build)
            const result = root.main() catch |err| {
                                    ^
???:?:?: 0x1805650df in ??? (???)
???:?:?: 0x84417fffffffffff in ??? (???)
error: the following build command crashed:
/Users/kjs/Code/src/github.com/scheibo/zigpkg/examples/zig/zig-cache/o/ef326fba59cfe32205e8b067e267b9ee/build /Users/kjs/Code/src/github.com/scheibo/zig/build/zig-macos-aarch64-0.12.0-dev.2036+fc79b22a9/zig /Users/kjs/Code/src/github.com/scheibo/zigpkg/examples/zig /Users/kjs/Code/src/github.com/scheibo/zigpkg/examples/zig/zig-cache /Users/kjs/.cache/zig --seed 0x142013d7 --summary all -Dadd run -- 40
make: *** [zig-example] Error 1
```

I tried adding a `build.zig.zon` to the root directory for `zigpkg` (even though I thought simple
projects weren't required to have one) and that did nothing to change the error.
https://ziglang.org/learn/build-system/ doesn't really offer any help here, nor does
https://zig.news/edyu/zig-package-manager-wtf-is-zon-558e, and looking at other Zig projects on
GitHub hasn't let me figure out what I'm doing wrong. ¯\\\_(ツ)_/¯

Some other thoughts on this (which might be completely unfounded given I couldn't get this to work):

- I don't know why `b.dependency` itself doesn't simply return a module, but I expect this is
  related to what hypothesis above about the build system support non-Zig projects.
- do I really need to specify the package name 3 times??? I assume that maybe one of these is to
  reference the name in the `build.zig.zon`, one is to allow for renaming the import (though why
  couldn't I just rename it in the `build.zig.zon` itself?) and the final one is maybe because
  perhaps a dependency can expose multiple modules? I'm not sure, it just seemed kind of silly to be
  typing out the same name all over the place - might be nice to streamline the common case here
- I'm not sure what happens if I don't specify `target`/`optimize` options to the `dependency` - I
  *assume* it will just use the same ones that the root uses, but it wasn't clear to me so I just
  passed them

The JS example was actually kind of easy, but the C example took quite a while to figure out how to
get it to work. With C I wanted to demonstrate how to use the artifacts produced by Zig as opposed
to simply also using the Zig build system here (which I expect would make it much easier, but I
don't want to force Zig onto downstream consumers). The [Makefile for the C
example](examples/c/Makefile) contains some comments about the ugliness around RPATH/macOS
versiongs/MinGW, but I think something here necessitated the `bundle_compiler_rt` above.

Finally, I really dislike that the recent build system changes removed the `main_pkg_path` option as
it basically forces me to restructure my project hierarchy (moving
`src/lib/bindings/{c,wasm.node}.zig` -> `src/lib/{c,wasm.node}.zig`). I'm willing to afford tools a
configuration file in my project root, but adding further files or forcing me to structure my
project a certain way always feels like overreach (the whole point of the config file is to be able
to tell said tool how my project is structured...). I originally tried to avoid restructuring by
creating a module the Zig package that the bindings would then all depend on as suggested by the PR
description, only this failed with errors related to the "build options not being accessible in the
root module(??)" and I didn't have the patience to deal with this.

A lot of this will likely be improved with time (or at the very least, after the system is settled
and documented so that the reasoning behind why things need to work they do is clear).