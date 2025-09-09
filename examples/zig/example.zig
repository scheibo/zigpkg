const std = @import("std");
const io = if (@hasDecl(std, "io")) std.io else std.Io;
const zigpkg = @import("zigpkg");

// In Zig the options may be set through a root declaration instead
// pub const zigpkg_options = .{ .multiply = false };

pub fn main() !void {
    // Set up required to be able to parse command line arguments
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Expect that we have been given a decimal number as our only argument
    if (args.len != 2) {
        try err("Usage: {s} <num>\n", .{args[0]});
        std.process.exit(1);
    }

    const num = std.fmt.parseUnsigned(u32, args[1], 10) catch {
        try err("Invalid number: {s}\n", .{args[1]});
        try err("Usage: {s} <num>\n", .{args[0]});
        std.process.exit(1);
    };

    try out("{d}\n", .{try zigpkg.compute(num)});
}

fn err(comptime fmt: []const u8, args: anytype) !void {
    if (@hasDecl(io, "getStdErr")) {
        try io.getStdErr().writer().print(fmt, args);
    } else {
        var writer = std.fs.File.stderr().writer(&.{});
        try writer.interface.print(fmt, args);
    }
}

fn out(comptime fmt: []const u8, args: anytype) !void {
    if (@hasDecl(io, "getStdOut")) {
        try io.getStdOut().writer().print(fmt, args);
    } else {
        var writer = std.fs.File.stdout().writer(&.{});
        try writer.interface.print(fmt, args);
    }
}
