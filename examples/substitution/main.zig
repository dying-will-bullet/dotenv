const std = @import("std");
const dotenv = @import("dotenv");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    try dotenv.loadFrom(allocator, ".env2", .{});

    std.debug.print(
        "VAR3=\"{s}\"\n",
        .{std.posix.getenv("VAR3") orelse ""},
    );
}
