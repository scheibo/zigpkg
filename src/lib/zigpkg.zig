const std = @import("std");

const options = @import("options.zig");

const expectEqual = std.testing.expectEqual;

pub fn add(n: u8) u8 {
  return n + if (options.foo) 1 else 2;
}

test "add2" {
  try expectEqual(@as(u8, if (options.foo) 7 else 8), add(6));
}
