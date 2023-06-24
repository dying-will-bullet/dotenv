const std = @import("std");
const testing = std.testing;
const parser = @import("./parser.zig");
const setenv = @import("./utils.zig").setenv;

const Error = error{
    LineParseError,
    EINVAL,
    ENOMEM,
};

pub const Options = struct {
    override: bool = false,
};

// https://github.com/ziglang/zig/wiki/Zig-Newcomer-Programming-FAQs#converting-from-t-to-0t
fn toCString(str: []const u8) ![std.fs.MAX_PATH_BYTES - 1:0]u8 {
    if (std.debug.runtime_safety) {
        std.debug.assert(std.mem.indexOfScalar(u8, str, 0) == null);
    }
    var path_with_null: [std.fs.MAX_PATH_BYTES - 1:0]u8 = undefined;

    if (str.len >= std.fs.MAX_PATH_BYTES) {
        return error.NameTooLong;
    }
    @memcpy(path_with_null[0..str.len], str);
    path_with_null[str.len] = 0;
    return path_with_null;
}

pub const Loader = struct {
    allocator: std.mem.Allocator,
    parser: parser.LineParser,
    options: Options,

    const Self = @This();

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

    pub fn envs(self: Self) std.StringHashMap(?[]const u8) {
        return self.parser.ctx;
    }

    pub fn load(self: *Self, reader: anytype) !void {
        while (true) {
            const line = try Self.readLine(self.allocator, reader);
            if (line == null) {
                return;
            }

            const result = try self.parser.parseLine(line.?);
            if (result == null) {
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
                    22 => return Error.EINVAL,
                    12 => return Error.EINVAL,
                    else => unreachable,
                }
            }
        }
    }

    fn readLine(allocator: std.mem.Allocator, reader: anytype) !?[]const u8 {
        var cur_state: ParseState = ParseState.complete;
        var buf_pos: usize = undefined;
        var cur_pos: usize = undefined;

        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();

        while (reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 1024)) |data| {
            buf_pos = buf.items.len;
            if (data == null) {
                if (cur_state == .complete) {
                    return null;
                } else {
                    return Error.LineParseError;
                }
            } else {
                defer allocator.free(data.?);
                if (data.?.len == 0) {
                    continue;
                }

                // // resotre newline
                try buf.appendSlice(data.?);
                try buf.append('\n');

                // TODO: strim more whitespce
                if (std.mem.startsWith(u8, std.mem.trimLeft(u8, buf.items, " "), "#")) {
                    return "";
                }
                const result = evalEndState(cur_state, buf.items[buf_pos..]);
                cur_pos = result.pos;
                cur_state = result.state;

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
                        try buf.resize(buf_pos + cur_pos);
                        return try buf.toOwnedSlice();
                    },
                    else => {},
                }
            }
        } else |err| {
            // TODO:?
            // if (err == error.EndOfStream) {
            //     if (cur_state == .complete) {
            //         return null;
            //     } else {
            //         return Error.LineParseError;
            //     }
            // }
            return err;
        }
    }
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

const State = struct {
    pos: usize,
    state: ParseState,
};

fn evalEndState(prev_state: ParseState, buf: []const u8) State {
    var cur_state = prev_state;
    var cur_pos: usize = 0;

    for (0.., buf) |pos, c| {
        cur_pos = pos;
        cur_state = switch (cur_state) {
            .whitespace => switch (c) {
                '#' => return State{ .pos = cur_pos, .state = .comment },
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

    return State{
        .pos = cur_pos,
        .state = cur_state,
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
