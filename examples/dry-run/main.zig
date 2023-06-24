const std = @import("std");
const Loader = @import("dotenv").Loader;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print(
        "Before => HOME={s}\n",
        .{std.os.getenv("HOME") orelse ""},
    );

    var loader = Loader(.{ .dry_run = true }).init(allocator);
    defer loader.deinit();

    try loader.loadFromFile(".env3");

    std.debug.print(
        "After  => HOME={s}\n",
        .{std.os.getenv("HOME") orelse ""},
    );

    std.debug.print("Process envs have not been modified!\n\n", .{});
    std.debug.print("Now list envs from the file:\n", .{});

    var it = loader.envs().iterator();
    while (it.next()) |*entry| {
        std.debug.print(
            "{s}={s}\n",
            .{ entry.key_ptr.*, entry.value_ptr.*.? },
        );
    }
}
