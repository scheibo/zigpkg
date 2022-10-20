const std = @import("std");
const zigpkg = @import("zigpkg");

pub fn main() !void {
    // Set up required to be able to parse command line arguments
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Expect that we have been given a decimal number as our only argument
    const err = std.io.getStdErr().writer();
    if (args.len != 2) {
        try err.print("Usage: {s} <num>\n", .{args[0]});
        std.process.exit(1);
    }

    const num = std.fmt.parseUnsigned(u64, args[1], 10) catch {
        try err.print("Invalid number: {s}\n", .{args[1]});
        try err.print("Usage: {s} <num>\n", .{args[0]});
        std.process.exit(1);
    };

    // TODO

    const out = std.io.getStdOut().writer();
    try out.print("{d}\n", .{num});
}
