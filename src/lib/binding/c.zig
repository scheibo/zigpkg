const zigpkg = @import("../zigpkg.zig");

export const zigpkg_options: zigpkg.Options = .{
    .foo = zigpkg.options.foo,
    .bar = zigpkg.options.bar,
    .baz = zigpkg.options.baz,
    .qux = zigpkg.options.qux,
};

export fn zigpkg_add(n: u8) u8 {
    return zigpkg.add(n);
}
