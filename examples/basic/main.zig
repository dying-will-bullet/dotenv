const std = @import("std");
const dotenv = @import("dotenv");

pub fn main(init: std.process.Init) !void {
    const before = init.environ_map.get("GITHUB_REPOSITORY") orelse "";
    std.debug.print("Before => GITHUB_REPOSITORY={s}\n", .{before});

    try dotenv.load(init.gpa, init.io, init.environ_map, .{});

    const after = init.environ_map.get("GITHUB_REPOSITORY") orelse "";
    std.debug.print("After  => GITHUB_REPOSITORY={s}\n", .{after});
}
