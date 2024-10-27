const std = @import("std");
const testing = std.testing;
const FileFinder = @import("./utils.zig").FileFinder;

pub const Loader = @import("./loader.zig").Loader;
/// Control loading behavior
pub const Options = @import("./loader.zig").Options;

/// Loads the `.env*` file from the current directory or parents.
///
/// If variables with the same names already exist in the environment, then their values will be
/// preserved when `options.override = false` (default behavior)
///
/// If you wish to ensure all variables are loaded from your `.env` file, ignoring variables
/// already existing in the environment, then pass `options.override = true`
///
/// Where multiple declarations for the same environment variable exist in `.env`
/// file, the *first one* will be applied.
pub fn load(allocator: std.mem.Allocator, comptime options: Options) !void {
    var finder = FileFinder.default();
    const path = try finder.find(allocator);
    defer allocator.free(path);

    try loadFrom(allocator, path, options);
}

/// Loads the `.env` file from the given path.
pub fn loadFrom(allocator: std.mem.Allocator, path: []const u8, comptime options: Options) !void {
    var loader = Loader(options).init(allocator);
    defer loader.deinit();

    try loader.loadFromFile(path);
}

pub fn getData(allocator: std.mem.Allocator) !std.StringHashMap(?[]const u8) {
    var finder = FileFinder.default();
    const path = try finder.find(allocator);

    return getDataFrom(allocator, path);
}

pub fn getDataFrom(allocator: std.mem.Allocator, path: []const u8) !std.StringHashMap(?[]const u8) {
    var loader = Loader(.{ .dry_run = true }).init(allocator);
    defer loader.deinit();

    try loader.loadFromFile(path);
    return loader.envs().move();
}

test "test load real file" {
    try testing.expect(std.posix.getenv("VAR1") == null);
    try testing.expect(std.posix.getenv("VAR2") == null);
    try testing.expect(std.posix.getenv("VAR3") == null);
    try testing.expect(std.posix.getenv("VAR4") == null);
    try testing.expect(std.posix.getenv("VAR5") == null);
    try testing.expect(std.posix.getenv("VAR6") == null);
    try testing.expect(std.posix.getenv("VAR7") == null);
    try testing.expect(std.posix.getenv("VAR8") == null);
    try testing.expect(std.posix.getenv("VAR9") == null);
    try testing.expect(std.posix.getenv("VAR10") == null);
    try testing.expect(std.posix.getenv("VAR11") == null);
    try testing.expect(std.posix.getenv("MULTILINE1") == null);
    try testing.expect(std.posix.getenv("MULTILINE2") == null);

    try loadFrom(testing.allocator, "./testdata/.env", .{});

    try testing.expectEqualStrings(std.posix.getenv("VAR1").?, "hello!");
    try testing.expectEqualStrings(std.posix.getenv("VAR2").?, "'quotes within quotes'");
    try testing.expectEqualStrings(std.posix.getenv("VAR3").?, "double quoted with # hash in value");
    try testing.expectEqualStrings(std.posix.getenv("VAR4").?, "single quoted with # hash in value");
    try testing.expectEqualStrings(std.posix.getenv("VAR5").?, "not_quoted_with_#_hash_in_value");
    try testing.expectEqualStrings(std.posix.getenv("VAR6").?, "not_quoted_with_comment_beheind");
    try testing.expectEqualStrings(std.posix.getenv("VAR7").?, "not quoted with escaped space");
    try testing.expectEqualStrings(std.posix.getenv("VAR8").?, "double quoted with comment beheind");
    try testing.expectEqualStrings(std.posix.getenv("VAR9").?, "Variable starts with a whitespace");
    try testing.expectEqualStrings(std.posix.getenv("VAR10").?, "Value starts with a whitespace after =");
    try testing.expectEqualStrings(std.posix.getenv("VAR11").?, "Variable ends with a whitespace before =");
    try testing.expectEqualStrings(std.posix.getenv("MULTILINE1").?, "First Line\nSecond Line");
    try testing.expectEqualStrings(
        std.posix.getenv("MULTILINE2").?,
        "# First Line Comment\nSecond Line\n#Third Line Comment\nFourth Line\n",
    );

    // try load(testing.allocator, .{});
}

test {
    std.testing.refAllDecls(@This());
}
