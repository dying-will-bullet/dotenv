const std = @import("std");
const testing = std.testing;

/// libc setenv
pub extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

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
    pub fn find(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        // TODO: allocator?
        var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const cwd = try std.process.getCwd(&buf);

        const path = try Self.recursiveFind(allocator, cwd, self.filename);
        return path;
    }

    /// Find a file and automatically look in the parent directory if it is not found.
    fn recursiveFind(allocator: std.mem.Allocator, dirname: []const u8, filename: []const u8) ![]const u8 {
        const path = try std.fs.path.join(allocator, &.{ dirname, filename });
        errdefer allocator.free(path);

        const f = std.fs.openFileAbsolute(path, .{}) catch |e| {
            // Find the file, but could not open it.
            if (e != std.fs.File.OpenError.FileNotFound) {
                return e;
            } else {
                // Not Found, try the parent dir
                if (std.fs.path.dirname(dirname)) |parent| {
                    return Self.recursiveFind(allocator, parent, filename);
                } else {
                    return std.fs.File.OpenError.FileNotFound;
                }
            }
        };
        defer f.close();

        // Check the path is a file.
        const metadata = try f.metadata();
        if (metadata.kind() == .file) {
            return path;
        }

        if (std.fs.path.dirname(dirname)) |parent| {
            return Self.recursiveFind(allocator, parent, filename);
        } else {
            return std.fs.File.OpenError.FileNotFound;
        }
    }
};

test "test found" {
    const allocator = testing.allocator;

    var finder = FileFinder.init("./testdata/.env");

    const path = try finder.find(allocator);
    allocator.free(path);
}

test "test not found" {
    const allocator = testing.allocator;

    var finder = FileFinder.init("balabalabala");

    const res = finder.find(allocator);
    try testing.expect(res == std.fs.File.OpenError.FileNotFound);
}
