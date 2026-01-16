const std = @import("std");
const zigpkg = @import("zigpkg");

// In Zig the options may be set through a root declaration instead
// pub const zigpkg_options = .{ .multiply = false };

pub fn main(init: std.process.Init) !void {
    // Set up required to be able to parse command line arguments
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var err = std.Io.File.stderr().writer(init.io, &.{});

    // Expect that we have been given a decimal number as our only argument
    if (args.len != 2) {
        try err.interface.print("Usage: {s} <num>\n", .{args[0]});
        std.process.exit(1);
    }

    const num = std.fmt.parseUnsigned(u32, args[1], 10) catch {
        try err.interface.print("Invalid number: {s}\n", .{args[1]});
        try err.interface.print("Usage: {s} <num>\n", .{args[0]});
        std.process.exit(1);
    };

    var out = std.Io.File.stdout().writer(init.io, &.{});
    try out.interface.print("{d}\n", .{try zigpkg.compute(num)});
}
