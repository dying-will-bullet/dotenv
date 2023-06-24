const std = @import("std");
const dotenv = @import("dotenv");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print(
        "Before => GITHUB_REPOSITORY={s}\n",
        .{std.os.getenv("GITHUB_REPOSITORY") orelse ""},
    );

    try dotenv.load(allocator, .{});

    std.debug.print(
        "After  => GITHUB_REPOSITORY={s}\n",
        .{std.os.getenv("GITHUB_REPOSITORY") orelse ""},
    );
}
