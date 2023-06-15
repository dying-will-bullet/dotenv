const std = @import("std");
const testing = std.testing;
const FileFinder = @import("./utils.zig").FileFinder;
const Loader = @import("./loader.zig").Loader;
const Options = @import("./loader.zig").Options;

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
pub fn load(allocator: std.mem.Allocator, options: Options) !void {
    var finder = FileFinder.default();
    const path = try finder.find(allocator);

    try loadFrom(allocator, path, options);
}

/// Loads the `.env*` file from the given path.
pub fn loadFrom(allocator: std.mem.Allocator, path: []const u8, options: Options) !void {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();

    var br = std.io.bufferedReader(f.reader());
    var reader = br.reader();

    var loader = Loader.init(allocator, options);
    defer loader.deinit();
    try loader.load(reader);
}

test "test load real file" {
    try testing.expect(std.os.getenv("CODEGEN_TEST_VAR1") == null);
    try testing.expect(std.os.getenv("CODEGEN_TEST_VAR2") == null);
    try testing.expect(std.os.getenv("CODEGEN_TEST_VAR3") == null);
    try testing.expect(std.os.getenv("CODEGEN_TEST_VAR4") == null);
    try testing.expect(std.os.getenv("CODEGEN_TEST_VAR5") == null);
    try testing.expect(std.os.getenv("CODEGEN_TEST_VAR6") == null);
    try testing.expect(std.os.getenv("CODEGEN_TEST_VAR7") == null);
    try testing.expect(std.os.getenv("CODEGEN_TEST_VAR8") == null);
    try testing.expect(std.os.getenv("CODEGEN_TEST_VAR9") == null);
    try testing.expect(std.os.getenv("CODEGEN_TEST_VAR10") == null);
    try testing.expect(std.os.getenv("CODEGEN_TEST_VAR11") == null);
    try testing.expect(std.os.getenv("CODEGEN_TEST_MULTILINE1") == null);
    try testing.expect(std.os.getenv("CODEGEN_TEST_MULTILINE2") == null);

    try loadFrom(testing.allocator, "./testdata/.env", .{});

    try testing.expectEqualStrings(std.os.getenv("CODEGEN_TEST_VAR1").?, "hello!");
    try testing.expectEqualStrings(std.os.getenv("CODEGEN_TEST_VAR2").?, "'quotes within quotes'");
    try testing.expectEqualStrings(std.os.getenv("CODEGEN_TEST_VAR3").?, "double quoted with # hash in value");
    try testing.expectEqualStrings(std.os.getenv("CODEGEN_TEST_VAR4").?, "single quoted with # hash in value");
    try testing.expectEqualStrings(std.os.getenv("CODEGEN_TEST_VAR5").?, "not_quoted_with_#_hash_in_value");
    try testing.expectEqualStrings(std.os.getenv("CODEGEN_TEST_VAR6").?, "not_quoted_with_comment_beheind");
    try testing.expectEqualStrings(std.os.getenv("CODEGEN_TEST_VAR7").?, "not quoted with escaped space");
    try testing.expectEqualStrings(std.os.getenv("CODEGEN_TEST_VAR8").?, "double quoted with comment beheind");
    try testing.expectEqualStrings(std.os.getenv("CODEGEN_TEST_VAR9").?, "Variable starts with a whitespace");
    try testing.expectEqualStrings(std.os.getenv("CODEGEN_TEST_VAR10").?, "Value starts with a whitespace after =");
    try testing.expectEqualStrings(std.os.getenv("CODEGEN_TEST_VAR11").?, "Variable ends with a whitespace before =");
    try testing.expectEqualStrings(std.os.getenv("CODEGEN_TEST_MULTILINE1").?, "First Line\nSecond Line");
    try testing.expectEqualStrings(
        std.os.getenv("CODEGEN_TEST_MULTILINE2").?,
        "# First Line Comment\nSecond Line\n#Third Line Comment\nFourth Line\n",
    );
}

test {
    std.testing.refAllDecls(@This());
}
