const std = @import("std");
const testing = std.testing;
const FileFinder = @import("./utils.zig").FileFinder;
const EnvMap = std.process.Environ.Map;

pub const Loader = @import("./loader.zig").Loader;
/// Control loading behavior
pub const Options = @import("./loader.zig").Options;

/// Loads the `.env*` file from the current directory or parents into `env_map`.
///
/// If variables with the same names already exist in `env_map`, then their values
/// will be preserved when `options.override = false` (default behavior).
///
/// If you wish to ensure all variables are loaded from your `.env` file, ignoring variables
/// already existing in the environment, then pass `options.override = true`
///
/// Where multiple declarations for the same environment variable exist in `.env`
/// file, the *first one* will be applied.
pub fn load(allocator: std.mem.Allocator, io: std.Io, env_map: *EnvMap, comptime options: Options) !void {
    var finder = FileFinder.default();
    const path = try finder.find(allocator, io);
    defer allocator.free(path);

    try loadFrom(allocator, io, env_map, path, options);
}

/// Loads the `.env` file from `path` into `env_map`.
pub fn loadFrom(allocator: std.mem.Allocator, io: std.Io, env_map: *EnvMap, path: []const u8, comptime options: Options) !void {
    var loader = Loader(options).init(allocator);
    defer loader.deinit();

    try loader.loadFromFile(io, env_map, path);
}

/// Loads the `.env*` file from the current directory or parents into a newly
/// allocated environment map. Caller owns the returned map and must deinit it.
pub fn loadAlloc(allocator: std.mem.Allocator, io: std.Io, comptime options: Options) !EnvMap {
    var finder = FileFinder.default();
    const path = try finder.find(allocator, io);
    defer allocator.free(path);

    return loadFromAlloc(allocator, io, path, options);
}

/// Loads the `.env` file from `path` into a newly allocated environment map.
/// Caller owns the returned map and must deinit it.
pub fn loadFromAlloc(allocator: std.mem.Allocator, io: std.Io, path: []const u8, comptime options: Options) !EnvMap {
    var env_map = EnvMap.init(allocator);
    errdefer env_map.deinit();

    try loadFrom(allocator, io, &env_map, path, options);
    return env_map;
}

/// Loads the `.env*` file from the current directory or parents into the C
/// process environment via libc `setenv`. This API is for C interop only.
pub fn loadC(allocator: std.mem.Allocator, io: std.Io, comptime options: Options) !void {
    var finder = FileFinder.default();
    const path = try finder.find(allocator, io);
    defer allocator.free(path);

    try loadFromC(allocator, io, path, options);
}

/// Loads the `.env` file from `path` into the C process environment via libc
/// `setenv`. This API requires linking libc.
pub fn loadFromC(allocator: std.mem.Allocator, io: std.Io, path: []const u8, comptime options: Options) !void {
    var loader = Loader(options).init(allocator);
    defer loader.deinit();

    var f = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer f.close(io);

    var buffer: [4096]u8 = undefined;
    var reader = f.readerStreaming(io, &buffer);
    try loader.loadIntoCEnv(&reader.interface);
}

test "test load real file" {
    var env_map = std.process.Environ.Map.init(testing.allocator);
    defer env_map.deinit();

    const io = std.Io.Threaded.global_single_threaded.io();
    try loadFrom(testing.allocator, io, &env_map, "./testdata/.env", .{});

    try testing.expectEqualStrings(env_map.get("VAR1").?, "hello!");
    try testing.expectEqualStrings(env_map.get("VAR2").?, "'quotes within quotes'");
    try testing.expectEqualStrings(env_map.get("VAR3").?, "double quoted with # hash in value");
    try testing.expectEqualStrings(env_map.get("VAR4").?, "single quoted with # hash in value");
    try testing.expectEqualStrings(env_map.get("VAR5").?, "not_quoted_with_#_hash_in_value");
    try testing.expectEqualStrings(env_map.get("VAR6").?, "not_quoted_with_comment_beheind");
    try testing.expectEqualStrings(env_map.get("VAR7").?, "not quoted with escaped space");
    try testing.expectEqualStrings(env_map.get("VAR8").?, "double quoted with comment beheind");
    try testing.expectEqualStrings(env_map.get("VAR9").?, "Variable starts with a whitespace");
    try testing.expectEqualStrings(env_map.get("VAR10").?, "Value starts with a whitespace after =");
    try testing.expectEqualStrings(env_map.get("VAR11").?, "Variable ends with a whitespace before =");
    try testing.expectEqualStrings(env_map.get("MULTILINE1").?, "First Line\nSecond Line");
    try testing.expectEqualStrings(
        env_map.get("MULTILINE2").?,
        "# First Line Comment\nSecond Line\n#Third Line Comment\nFourth Line\n",
    );
}

test "loadFrom respects existing Environ.Map values unless override is enabled" {
    const allocator = testing.allocator;
    var env_map = std.process.Environ.Map.init(allocator);
    defer env_map.deinit();

    try env_map.put("HOME", "/home/existing");
    const input = "HOME=/home/dotenv\nNEW_VALUE=yes\n";
    var reader = std.Io.Reader.fixed(input);

    var loader = Loader(.{}).init(allocator);
    defer loader.deinit();
    try loader.loadIntoMap(&env_map, &reader);

    try testing.expectEqualStrings("/home/existing", env_map.get("HOME").?);
    try testing.expectEqualStrings("yes", env_map.get("NEW_VALUE").?);

    var override_reader = std.Io.Reader.fixed(input);
    var override_loader = Loader(.{ .override = true }).init(allocator);
    defer override_loader.deinit();
    try override_loader.loadIntoMap(&env_map, &override_reader);

    try testing.expectEqualStrings("/home/dotenv", env_map.get("HOME").?);
}

test "loadFrom uses Environ.Map as substitution fallback" {
    const allocator = testing.allocator;
    var env_map = std.process.Environ.Map.init(allocator);
    defer env_map.deinit();

    try env_map.put("BASE_DIR", "/opt/app");

    const input = "CONFIG_DIR=${BASE_DIR}/config\n";
    var reader = std.Io.Reader.fixed(input);

    var loader = Loader(.{}).init(allocator);
    defer loader.deinit();
    try loader.loadIntoMap(&env_map, &reader);

    try testing.expectEqualStrings("/opt/app/config", env_map.get("CONFIG_DIR").?);
}

test "loadFromAlloc returns an owned Environ.Map" {
    const io = std.Io.Threaded.global_single_threaded.io();
    var env_map = try loadFromAlloc(testing.allocator, io, "./testdata/.env", .{});
    defer env_map.deinit();

    try testing.expectEqualStrings("hello!", env_map.get("VAR1").?);
}

test "loadFromC writes to libc environment" {
    const io = std.Io.Threaded.global_single_threaded.io();
    try loadFromC(testing.allocator, io, "./testdata/.env", .{ .override = true });

    try testing.expectEqualStrings("hello!", std.mem.span(std.c.getenv("VAR1").?));
}

test {
    std.testing.refAllDecls(@This());
}
