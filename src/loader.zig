const std = @import("std");
const parser = @import("./parser.zig");
const setenv = @import("./utils.zig").setenv;
const toCString = @import("./utils.zig").toCString;
const Error = @import("./error.zig").Error;

const testing = std.testing;

pub const Options = struct {
    /// override existed env value, default `false`
    override: bool = false,
    /// read and collect environment variables, but do not write them to the environment.
    dry_run: bool = false,
};

const ParseState = enum {
    complete,
    escape,
    strong_open,
    strong_open_escape,
    weak_open,
    weak_open_escape,
    comment,
    whitespace,
};

pub const Loader = struct {
    allocator: std.mem.Allocator,
    parser: parser.LineParser,
    options: Options,

    const Self = @This();

    // --------------------------------------------------------------------------------
    //                                  Public API
    // --------------------------------------------------------------------------------

    pub fn init(allocator: std.mem.Allocator, options: Options) Self {
        return Self{
            .allocator = allocator,
            .parser = parser.LineParser.init(allocator),
            .options = options,
        };
    }

    pub fn deinit(self: *Self) void {
        self.parser.deinit();
    }

    pub fn envs(self: *Self) *const std.StringHashMap(?[]const u8) {
        return &self.parser.ctx;
    }

    pub fn load(self: *Self, reader: anytype) !void {
        while (true) {
            // read a logical line.
            const line = try self.readLine(reader);
            if (line == null) {
                return;
            }

            const result = try self.parser.parseLine(line.?);
            if (result == null) {
                continue;
            }

            if (self.options.dry_run) {
                continue;
            }

            const key = try toCString(result.?.key);
            const value = try toCString(result.?.value);

            // https://man7.org/linux/man-pages/man3/setenv.3.html
            var err_code: c_int = undefined;
            if (self.options.override) {
                err_code = setenv(&key, &value, 1);
            } else {
                err_code = setenv(&key, &value, 0);
            }

            self.allocator.free(line.?);

            if (err_code != 0) {
                switch (err_code) {
                    22 => return Error.InvalidValue,
                    12 => return error.OutOfMemory,
                    else => unreachable,
                }
            }
        }
    }

    // --------------------------------------------------------------------------------
    //                                  Core API
    // --------------------------------------------------------------------------------

    /// Read a logical line.
    /// Multiple lines enclosed in quotation marks are considered as a single line.
    /// e.g.
    /// ```
    /// a = "Line1
    /// Line2"
    /// ```
    /// It will be returned as a single line.
    fn readLine(self: Self, reader: anytype) !?[]const u8 {
        var cur_state: ParseState = ParseState.complete;
        var buf_pos: usize = undefined;
        var cur_pos: usize = undefined;

        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();

        // TODO: line size
        // someone may use JSON text as the value for the env var.
        var line_buf: [1024]u8 = undefined;
        while (reader.readUntilDelimiterOrEof(&line_buf, '\n')) |data| {
            buf_pos = buf.items.len;
            if (data == null) {
                if (cur_state == .complete) {
                    return null;
                } else {
                    return Error.ParseError;
                }
            } else {
                if (data.?.len == 0) {
                    continue;
                }

                try buf.appendSlice(data.?);
                // resotre newline
                try buf.append('\n');

                if (std.mem.startsWith(u8, std.mem.trimLeft(
                    u8,
                    buf.items,
                    // ASCII Whitespace
                    &[_]u8{ ' ', '\x09', '\x0a', '\x0b', '\x0c', '\x0d' },
                ), "#")) {
                    return "";
                }

                const result = nextState(cur_state, buf.items[buf_pos..]);
                cur_pos = result.new_pos;
                cur_state = result.new_state;

                switch (cur_state) {
                    .complete => {
                        if (std.mem.endsWith(u8, buf.items, "\n")) {
                            _ = buf.pop();
                            if (std.mem.endsWith(u8, buf.items, "\r")) {
                                _ = buf.pop();
                            }
                        }
                        return try buf.toOwnedSlice();
                    },
                    .comment => {
                        // truncate
                        try buf.resize(buf_pos + cur_pos);
                        return try buf.toOwnedSlice();
                    },
                    else => {
                        //  do nothing
                    },
                }
            }
        } else |err| {
            return err;
        }
    }
};

fn nextState(prev_state: ParseState, buf: []const u8) struct { new_pos: usize, new_state: ParseState } {
    var cur_state = prev_state;
    var cur_pos: usize = 0;

    for (0.., buf) |pos, c| {
        cur_pos = pos;
        cur_state = switch (cur_state) {
            .whitespace => switch (c) {
                '#' => return .{ .new_pos = cur_pos, .new_state = .comment },
                '\\' => .escape,
                '"' => .weak_open,
                '\'' => .strong_open,
                else => .complete,
            },
            .escape => .complete,
            .complete => switch (c) {
                '\\' => .escape,
                '"' => .weak_open,
                '\'' => .strong_open,
                else => blk: {
                    if (std.ascii.isWhitespace(c) and c != '\n' and c != '\r') {
                        break :blk .whitespace;
                    } else {
                        break :blk .complete;
                    }
                },
            },
            .weak_open => switch (c) {
                '\\' => .weak_open_escape,
                '"' => .complete,
                else => .weak_open,
            },
            .weak_open_escape => .weak_open,
            .strong_open => switch (c) {
                '\\' => .strong_open_escape,
                '\'' => .complete,
                else => .strong_open,
            },
            .strong_open_escape => .strong_open,
            .comment => unreachable,
        };
    }

    return .{
        .new_pos = cur_pos,
        .new_state = cur_state,
    };
}

test "test load" {
    const allocator = testing.allocator;
    const input =
        \\KEY0=0
        \\KEY1="1"
        \\KEY2='2'
        \\KEY3='th ree'
        \\KEY4="fo ur"
        \\KEY5=f\ ive
        \\KEY6=
        \\KEY7=   # foo
        \\KEY8  ="whitespace before ="
        \\KEY9=    "whitespace after ="
    ;

    var fbs = std.io.fixedBufferStream(input);
    var reader = fbs.reader();

    var loader = Loader.init(allocator, .{});
    defer loader.deinit();
    try loader.load(reader);

    try testing.expectEqualStrings(loader.envs().get("KEY0").?.?, "0");
    try testing.expectEqualStrings(loader.envs().get("KEY1").?.?, "1");
    try testing.expectEqualStrings(loader.envs().get("KEY2").?.?, "2");
    try testing.expectEqualStrings(loader.envs().get("KEY3").?.?, "th ree");
    try testing.expectEqualStrings(loader.envs().get("KEY4").?.?, "fo ur");
    try testing.expectEqualStrings(loader.envs().get("KEY5").?.?, "f ive");
    try testing.expect(loader.envs().get("KEY6").? == null);
    try testing.expect(loader.envs().get("KEY7").? == null);
    try testing.expectEqualStrings(loader.envs().get("KEY8").?.?, "whitespace before =");
    try testing.expectEqualStrings(loader.envs().get("KEY9").?.?, "whitespace after =");

    const r = std.os.getenv("KEY0");
    try testing.expectEqualStrings(r.?, "0");
}

test "test multiline" {
    const allocator = testing.allocator;
    const input =
        \\C="F
        \\S"
    ;

    var fbs = std.io.fixedBufferStream(input);
    var reader = fbs.reader();

    var loader = Loader.init(allocator, .{});
    defer loader.deinit();
    try loader.load(reader);

    try testing.expectEqualStrings(loader.envs().get("C").?.?, "F\nS");
}

test "test not override" {
    const allocator = testing.allocator;
    const input =
        \\HOME=/home/nayuta
    ;

    var fbs = std.io.fixedBufferStream(input);
    var reader = fbs.reader();

    var loader = Loader.init(allocator, .{ .override = false });
    defer loader.deinit();
    try loader.load(reader);

    const r = std.os.getenv("HOME");
    try testing.expect(!std.mem.eql(u8, r.?, "/home/nayuta"));
}

test "test override" {
    const allocator = testing.allocator;
    const input =
        \\HOME=/home/nayuta
    ;

    var fbs = std.io.fixedBufferStream(input);
    var reader = fbs.reader();

    var loader = Loader.init(allocator, .{ .override = true });
    defer loader.deinit();
    try loader.load(reader);

    const r = std.os.getenv("HOME");
    try testing.expect(std.mem.eql(u8, r.?, "/home/nayuta"));
}
