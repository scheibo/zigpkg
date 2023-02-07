const zigpkg = @import("../zigpkg.zig");

export const ZIGPKG_OPTIONS: zigpkg.Options = .{
    .foo = zigpkg.options.foo,
    .bar = zigpkg.options.bar,
    .baz = zigpkg.options.baz,
    .qux = zigpkg.options.qux,
};

export fn zigpkg_add(n: u8) u8 {
    return zigpkg.add(n);
}
