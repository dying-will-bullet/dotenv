const std = @import("std");
const dotenv = @import("dotenv");

pub fn main(init: std.process.Init) !void {
    try dotenv.loadFrom(init.gpa, init.io, init.environ_map, ".env2", .{});

    std.debug.print("VAR3=\"{s}\"\n", .{init.environ_map.get("VAR3") orelse ""});
}
