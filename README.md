<h1 align="center"> dotenv 🌴 </h1>

[![CI](https://github.com/dying-will-bullet/dotenv/actions/workflows/ci.yaml/badge.svg)](https://github.com/dying-will-bullet/dotenv/actions/workflows/ci.yaml)
[![codecov](https://codecov.io/gh/dying-will-bullet/dotenv/branch/master/graph/badge.svg?token=D8DHON0VE5)](https://codecov.io/gh/dying-will-bullet/dotenv)
![](https://img.shields.io/badge/language-zig-%23ec915c)

dotenv is a library that loads environment variables from a `.env` file into `std.os.environ`.
Storing configuration in the environment separate from code is based on The
[Twelve-Factor](http://12factor.net/config) App methodology.

This library is a Zig language port of [nodejs dotenv](https://github.com/motdotla/dotenv).

## Quick Start

Automatically find the `.env` file and load the variables into the process environment with just one line.

```zig
const std = @import("std");
const dotenv = @import("dotenv");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    try dotenv.load(allocator, .{});
}
```

By default, it will search for a file named `.env` in the working directory and its parent directories recursively.
Of course, you can specify a path if desired.

```zig
pub fn main() !void {
    try dotenv.loadFrom(allocator, "/app/.env", .{});
}
```

**Since writing to `std.os.environ` requires a C `setenv` call, linking with C is necessary.**

If you only want to read and parse the contents of the `.env` file, you can try the following.

```zig
pub fn main() !void {
    var envs = try dotenv.getDataFrom(allocator, ".env");

    var it = envs.iterator();
    while (it.next()) |*entry| {
        std.debug.print(
            "{s}={s}\n",
            .{ entry.key_ptr.*, entry.value_ptr.*.? },
        );
    }
}
```

This does not require linking with a C library.
The caller owns the memory, so you need to free both the key and value in the hashmap.

## `.env` Syntax

```
NAME_1="VALUE_1"
NAME_2='VALUE_2'
NAME_3=VALUE_3
```

#### Multiline values

The value of a variable can span multiple lines(quotes are required).

```
PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
ABCD...
-----END RSA PRIVATE KEY-----"
```

#### Comments

Comments start with a `#`.

```
# This is a comment
NAME="VALUE" # comment
```

#### Variable Expansion

You can reference a variable using `${}`, and the variable should be defined earlier.

```
HO="/home"
ME="/koyori"

HOME="${HO}${ME}"  # equal to HOME=/home/koyori
```

## LICENSE

MIT License Copyright (c) 2023, Hanaasagi
