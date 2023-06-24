const std = @import("std");
const dotenv = @import("dotenv");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    try dotenv.loadFrom(allocator, ".env3", .{});
    std.debug.print(
        "VAR=\"{s}\"\n",
        .{std.os.getenv("VAR") orelse ""},
    );
}
