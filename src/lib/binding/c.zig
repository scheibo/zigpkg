const zigpkg = @import("../zigpkg.zig");

export const ZIGPKG_OPTIONS: extern struct { add: bool, subtract: bool } = .{
    .add = zigpkg.options.add,
    .subtract = zigpkg.options.subtract,
};

export fn zigpkg_compute(n: *u32) bool {
    n.* = zigpkg.compute(n.*) catch return false;
    return true;
}
