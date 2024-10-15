const std = @import("std");
const Error = @import("./error.zig").Error;

const testing = std.testing;

const SubstitutionMode = enum {
    none,
    block,
    escaped_block,
};

/// Parsed Result
pub const ParsedResult = struct {
    // Key
    key: []const u8,
    // Value
    value: []const u8,
};

// /// Parse a line and returns the parsed result.
// pub fn parseLine(line: []const u8, ctx: *std.StringHashMap(?[]const u8)) !?ParsedResult {
//     var parser = LineParser.init(line, ctx);
//     return try parser.parseLine();
// }

/// Line Parser
pub const LineParser = struct {
    /// Context
    ctx: std.StringHashMap(?[]const u8),
    /// Line data
    line: []const u8,
    /// position
    pos: usize,

    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .ctx = std.StringHashMap(?[]const u8).init(allocator),
            .line = "",
            .pos = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.ctx.iterator();
        while (it.next()) |*entry| {
            self.allocator.free(entry.key_ptr.*);
            if (entry.value_ptr.* != null) {
                self.allocator.free(entry.value_ptr.*.?);
            }
        }

        self.ctx.deinit();
    }

    /// Skip whitespace character
    fn skipWhitespace(self: *Self) void {
        var i: usize = 0;

        while (i < self.line.len) {
            if (!std.ascii.isWhitespace(self.line[i])) {
                break;
            }

            i += 1;
        }

        self.pos += i;
        self.line = self.line[i..];
    }

    /// Next character should be `=`
    fn expectEqual(self: *Self) !void {
        if (!std.mem.startsWith(u8, self.line, "=")) {
            return Error.InvalidValue;
        }

        self.line = self.line[1..];
        self.pos += 1;
    }

    /// Parse a key
    fn parseKey(self: *Self) ![]const u8 {
        std.debug.assert(self.line.len > 0);

        const first_char = self.line[0];

        if (!std.ascii.isAlphabetic(first_char) or first_char == '_') {
            return Error.InvalidKey;
        }

        var i: usize = 0;

        while (i < self.line.len) {
            if (!(std.ascii.isAlphanumeric(self.line[i]) or self.line[i] == '_' or self.line[i] == '.')) {
                break;
            }
            i += 1;
        }

        self.pos += i;
        const key = self.line[0..i];
        self.line = self.line[i..];

        return self.allocator.dupe(u8, key);
    }

    /// Parse a value
    fn parseValue(self: *Self) ![]const u8 {
        var strong_quote = false; // '
        var weak_quote = false; // "
        var escaped = false;
        var expecting_end = false;

        var output_buf = std.ArrayList(u8).init(self.allocator);
        defer output_buf.deinit();
        var output = output_buf.writer();

        var substitution_mode = SubstitutionMode.none;

        var name_buf = std.ArrayList(u8).init(self.allocator);
        defer name_buf.deinit();
        var substitution_name = name_buf.writer();

        for (0.., self.line) |i, c| {
            _ = i;
            if (expecting_end) {
                if (c == ' ' or c == '\t') {
                    continue;
                } else if (c == '#') {
                    break;
                } else {
                    return Error.InvalidValue;
                }
            } else if (escaped) {
                if (c == '\\' or c == '\'' or c == '"' or c == '$' or c == ' ') {
                    try output.writeByte(c);
                } else if (c == 'n') {
                    try output.writeByte('\n');
                } else {
                    return Error.InvalidValue;
                }

                escaped = false;
            } else if (strong_quote) {
                if (c == '\'') {
                    strong_quote = false;
                } else {
                    try output.writeByte(c);
                }
            } else if (substitution_mode != .none) {
                if (std.ascii.isAlphanumeric(c)) {
                    try substitution_name.writeByte(c);
                } else {
                    switch (substitution_mode) {
                        .none => unreachable,
                        .block => {
                            if (c == '{' and name_buf.items.len == 0) {
                                substitution_mode = .escaped_block;
                            } else {
                                try substitute_variables(&self.ctx, name_buf.items, output);
                                name_buf.clearRetainingCapacity();
                                if (c == '$') {
                                    if (!strong_quote and !escaped) {
                                        substitution_mode = .block;
                                    } else {
                                        substitution_mode = .none;
                                    }
                                } else {
                                    substitution_mode = .none;
                                    try output.writeByte(c);
                                }
                            }
                        },
                        .escaped_block => {
                            if (c == '}') {
                                substitution_mode = .none;
                                try substitute_variables(&self.ctx, name_buf.items, output);
                                name_buf.clearRetainingCapacity();
                            } else {
                                try substitution_name.writeByte(c);
                            }
                        },
                    }
                }
            } else if (c == '$') {
                if (!strong_quote and !escaped) {
                    substitution_mode = .block;
                } else {
                    substitution_mode = .none;
                }
            } else if (weak_quote) {
                if (c == '"') {
                    weak_quote = false;
                } else if (c == '\\') {
                    escaped = true;
                } else {
                    try output.writeByte(c);
                }
            } else if (c == '\'') {
                strong_quote = true;
            } else if (c == '"') {
                weak_quote = true;
            } else if (c == '\\') {
                escaped = true;
            } else if (c == ' ' or c == '\t') {
                expecting_end = true;
            } else {
                try output.writeByte(c);
            }
        }

        if (substitution_mode == .escaped_block or strong_quote or weak_quote) {
            return Error.InvalidValue;
        } else {
            try substitute_variables(&self.ctx, name_buf.items, output);
            name_buf.clearRetainingCapacity();
            return output_buf.toOwnedSlice();
        }
    }

    pub fn parseLine(self: *Self, line: []const u8) !?ParsedResult {
        // Reset line data and state
        self.line = line;
        self.pos = 0;

        self.skipWhitespace();
        if (self.line.len == 0 or std.mem.startsWith(u8, self.line, "#")) {
            return null;
        }

        var key = try self.parseKey();
        self.skipWhitespace();

        // export can be either an optional prefix or a key itself
        if (std.mem.eql(u8, key, "export")) {
            // here we check for an optional `=`, below we throw directly when it’s not found.
            self.expectEqual() catch {
                self.allocator.free(key);

                key = try self.parseKey();
                self.skipWhitespace();
                try self.expectEqual();
            };
        } else {
            try self.expectEqual();
        }

        self.skipWhitespace();

        if (self.line.len == 0 or std.mem.startsWith(u8, self.line, "#")) {
            try self.ctx.put(key, null);
            return ParsedResult{ .key = key, .value = "" };
        }

        const parsed_value = try self.parseValue();
        try self.ctx.put(key, parsed_value);

        return ParsedResult{ .key = key, .value = parsed_value };
    }
};

/// handle `KEY=${KEY_XXX}`
/// First, search `KEY_XXX` from the environment variables,
/// and then from the context.
fn substitute_variables(
    ctx: *std.StringHashMap(?[]const u8),
    name: []const u8,
    output: anytype,
) !void {
    if (std.posix.getenv(name)) |value| {
        _ = try output.write(value);
    } else {
        const value = ctx.get(name) orelse "";
        _ = try output.write(value.?);
    }
}

test "test parse" {
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
        \\KEY10=${KEY0}?${KEY1}
        \\export KEY11=tmux-256color
    ;

    const expect = [_]?[]const u8{
        "0",
        "1",
        "2",
        "th ree",
        "fo ur",
        "f ive",
        null,
        null,
        "whitespace before =",
        "whitespace after =",
        "0?1",
        "tmux-256color",
    };

    var parser = LineParser.init(allocator);
    defer parser.deinit();

    var it = std.mem.split(u8, input, "\n");
    var i: usize = 0;
    while (it.next()) |line| {
        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();

        try buf.writer().print("KEY{d}", .{i});
        const key = buf.items;

        _ = try parser.parseLine(line);

        try testing.expect(parser.ctx.get(key) != null);

        if (expect[i] == null) {
            const value = parser.ctx.get(key).?;
            try testing.expect(value == null);
        } else {
            const value = parser.ctx.get(key).?.?;
            try testing.expectEqualStrings(expect[i].?, value);
        }

        i += 1;
    }
}
