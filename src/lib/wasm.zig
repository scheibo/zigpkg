const zigpkg = @import("./zigpkg.zig");

export const ADD = zigpkg.options.add;
export const SUBTRACT = zigpkg.options.subtract;

extern fn overflow() void;

export fn compute(n: u32) u32 {
    return zigpkg.compute(n) catch err: {
        overflow();
        break :err 0;
    };
}
