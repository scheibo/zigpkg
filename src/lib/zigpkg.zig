const std = @import("std");

pub const options = @import("options.zig");
pub const Options = options.Options;

const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;

const Error = if (options.divide) error{ Overflow, DivisionByZero } else error{Overflow};

pub fn compute(n: u32) Error!u32 {
    var m = n;
    if (options.add) m = try std.math.add(u32, n, 2);
    if (options.subtract) m = try std.math.sub(u32, m, 5);
    if (options.multiply) m = try std.math.mul(u32, m, 3);
    if (options.divide) m = try std.math.divTrunc(u32, m, 4);
    return m;
}

test "compute" {
    if (options.add and options.subtract) {
        try expectEqual(@as(u32, 1), try compute(4));
        try expectError(error.Overflow, compute(std.math.maxInt(u32)));
        try expectError(error.Overflow, compute(0));
    } else if (options.add) {
        try expectEqual(@as(u32, 7), try compute(5));
        try expectError(error.Overflow, compute(std.math.maxInt(u32)));
    } else if (options.subtract) {
        try expectEqual(@as(u32, 5), try compute(10));
        try expectError(error.Overflow, compute(4));
    } else {
        try expectEqual(@as(u32, 13), try compute(13));
    }
}
