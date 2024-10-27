const std = @import("std");
const dotenv = @import("dotenv");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print(
        "Before => HOME={s}\n",
        .{std.posix.getenv("HOME") orelse ""},
    );

    var envs = try dotenv.getDataFrom(allocator, "./.env3");

    std.debug.print(
        "After  => HOME={s}\n",
        .{std.posix.getenv("HOME") orelse ""},
    );

    std.debug.print("Process envs have not been modified!\n\n", .{});
    std.debug.print("Now list envs from the file:\n", .{});

    var it = envs.iterator();
    while (it.next()) |*entry| {
        std.debug.print(
            "{s}={s}\n",
            .{ entry.key_ptr.*, entry.value_ptr.*.? },
        );
    }
}
