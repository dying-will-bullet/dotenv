const std = @import("std");
const dotenv = @import("dotenv");

pub fn main(init: std.process.Init) !void {
    const before = init.environ_map.get("HOME") orelse "";
    std.debug.print("Before => HOME={s}\n", .{before});

    var envs = try dotenv.loadFromAlloc(init.gpa, init.io, "./.env3", .{});
    defer envs.deinit();

    const after = init.environ_map.get("HOME") orelse "";
    std.debug.print("After  => HOME={s}\n", .{after});

    std.debug.print("Application env map has not been modified!\n\n", .{});
    std.debug.print("Now list envs from the file:\n", .{});

    for (envs.keys(), envs.values()) |key, value| {
        std.debug.print(
            "{s}={s}\n",
            .{ key, value },
        );
    }
}
