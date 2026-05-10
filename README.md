<h1 align="center"> dotenv 🌴 </h1>

[![CI](https://github.com/dying-will-bullet/dotenv/actions/workflows/ci.yaml/badge.svg)](https://github.com/dying-will-bullet/dotenv/actions/workflows/ci.yaml)
<!-- [![codecov](https://codecov.io/gh/dying-will-bullet/dotenv/branch/master/graph/badge.svg?token=D8DHON0VE5)](https://codecov.io/gh/dying-will-bullet/dotenv) -->
![](https://img.shields.io/badge/language-zig-%23ec915c)

dotenv is a library that parses variables from a `.env` file.
Storing configuration in the environment separate from code is based on The
[Twelve-Factor](http://12factor.net/config) App methodology.

This library is a Zig language port of [nodejs dotenv](https://github.com/motdotla/dotenv).

Target Zig version: 0.16.0

## Zig 0.16 API

Zig 0.16 no longer exposes process environment variables as mutable global state through the standard library.
The recommended model is for the application to receive `std.process.Init` in `main`, then pass `init.io` and `init.environ_map` to dotenv.

```zig
pub fn main(init: std.process.Init) !void {
    try dotenv.load(init.gpa, init.io, init.environ_map, .{});

    if (init.environ_map.get("DATABASE_URL")) |database_url| {
        std.debug.print("DATABASE_URL={s}\n", .{database_url});
    }
}
```

For compatibility with C libraries, dotenv also provides `loadC` and `loadFromC`, which call libc `setenv` and require linking libc.

## Quick Start

Automatically find the `.env` file and load the variables into the application environment map.

```zig
const std = @import("std");
const dotenv = @import("dotenv");

pub fn main(init: std.process.Init) !void {
    try dotenv.load(init.gpa, init.io, init.environ_map, .{});
}
```

By default, it will search for a file named `.env` in the working directory and its parent directories recursively.
Of course, you can specify a path if desired.

```zig
pub fn main(init: std.process.Init) !void {
    try dotenv.loadFrom(init.gpa, init.io, init.environ_map, "/app/.env", .{});
}
```

The Zig-native APIs do not require libc. Only the optional `loadC` / `loadFromC` compatibility path needs libc.

If you only want to read and parse the contents of the `.env` file, you can try the following.

```zig
pub fn main(init: std.process.Init) !void {
    var envs = try dotenv.loadFromAlloc(init.gpa, init.io, ".env", .{});
    defer envs.deinit();

    for (envs.keys(), envs.values()) |key, value| {
        std.debug.print(
            "{s}={s}\n",
            .{ key, value },
        );
    }
}
```

This does not require linking with a C library.
The caller owns the returned `std.process.Environ.Map` and must call `deinit`.

## API

- `load(allocator, io, env_map, options)`: find `.env` from the current directory or parents and load it into `env_map`.
- `loadFrom(allocator, io, env_map, path, options)`: load variables from `path` into `env_map`.
- `loadAlloc(allocator, io, options)`: find `.env` and return a newly allocated `std.process.Environ.Map`.
- `loadFromAlloc(allocator, io, path, options)`: load `path` and return a newly allocated `std.process.Environ.Map`.
- `loadC(allocator, io, options)`: find `.env` and write variables to the C process environment with `setenv`.
- `loadFromC(allocator, io, path, options)`: load `path` and write variables to the C process environment with `setenv`.

`options.override` defaults to `false`, so existing keys in the target map or C environment are preserved unless you pass `.{ .override = true }`.

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

MIT License Copyright (c) 2023-2025, Hanaasagi
