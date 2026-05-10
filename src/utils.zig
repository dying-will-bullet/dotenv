const std = @import("std");
const testing = std.testing;

/// libc setenv
pub extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

// https://github.com/ziglang/zig/wiki/Zig-Newcomer-Programming-FAQs#converting-from-t-to-0t
pub fn toCString(str: []const u8) ![std.fs.max_path_bytes - 1:0]u8 {
    if (std.debug.runtime_safety) {
        std.debug.assert(std.mem.indexOfScalar(u8, str, 0) == null);
    }
    var path_with_null: [std.fs.max_path_bytes - 1:0]u8 = undefined;

    if (str.len >= std.fs.max_path_bytes) {
        return error.NameTooLong;
    }
    @memcpy(path_with_null[0..str.len], str);
    path_with_null[str.len] = 0;
    return path_with_null;
}

/// Default File name
const default_file_name = ".env";

/// Use to find an env file starting from the current directory and going upwards.
pub const FileFinder = struct {
    filename: []const u8,

    const Self = @This();

    pub fn init(filename: []const u8) Self {
        return Self{
            .filename = filename,
        };
    }

    /// Default filename is `.env`
    pub fn default() Self {
        return Self.init(default_file_name);
    }

    /// Find the file and return absolute path.
    /// The return value should be freed by caller.
    pub fn find(self: Self, allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
        // TODO: allocator?
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const len = try std.process.currentPath(io, &buf);
        const cwd = buf[0..len];

        const path = try Self.recursiveFind(allocator, io, cwd, self.filename);
        return path;
    }

    /// Find a file and automatically look in the parent directory if it is not found.
    fn recursiveFind(allocator: std.mem.Allocator, io: std.Io, dirname: []const u8, filename: []const u8) ![]const u8 {
        const path = try std.fs.path.join(allocator, &.{ dirname, filename });

        const f = std.Io.Dir.openFileAbsolute(io, path, .{}) catch |e| {
            // Find the file, but could not open it.
            if (e != std.Io.File.OpenError.FileNotFound) {
                allocator.free(path);
                return e;
            } else {
                // Not Found, try the parent dir
                if (std.fs.path.dirname(dirname)) |parent| {
                    allocator.free(path); // situation not captured by errdefer
                    return Self.recursiveFind(allocator, io, parent, filename);
                } else {
                    allocator.free(path);
                    return std.Io.File.OpenError.FileNotFound;
                }
            }
        };
        defer f.close(io);

        // Check the path is a file.
        if ((try f.stat(io)).kind == .file) {
            return path;
        }

        if (std.fs.path.dirname(dirname)) |parent| {
            allocator.free(path);
            return Self.recursiveFind(allocator, io, parent, filename);
        } else {
            allocator.free(path);
            return std.Io.File.OpenError.FileNotFound;
        }
    }
};

test "test found" {
    const allocator = testing.allocator;

    var finder = FileFinder.init("./testdata/.env");

    const io = std.Io.Threaded.global_single_threaded.io();
    const path = try finder.find(allocator, io);
    allocator.free(path);
}

test "test not found" {
    const allocator = testing.allocator;

    var finder = FileFinder.init("balabalabala");

    const io = std.Io.Threaded.global_single_threaded.io();
    const res = finder.find(allocator, io);
    try testing.expect(res == std.Io.File.OpenError.FileNotFound);
}
