# Autobahn

```
  o----------------o
  |                |
  |      /||\      |
  |     /_||_\     |
  | =m==========m= |
  |   /   ||   \   |
  |  /____||____\  |
  |                |
  o----------------o
```

A simple parallel map implementation.

## Usage with internal memory allocation

Using `Autobahn` is easy.
It's so small you can just copy and paste it into your project.

```zig
const std = @import("std");
const Autobahn = @import("autobahn").Autobahn;

pub fn main() !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();

    const lane_count = 4;
    const size = 400_000;

    var pool: std.Thread.Pool = undefined;
    try pool.init(std.Thread.Pool.Options{ .allocator = arena.allocator(), .n_jobs = lane_count });
    var wg = std.Thread.WaitGroup{};

    var in: std.ArrayList(u32) = try .initCapacity(arena.allocator(), size);
    for (0..in.capacity) |i| in.appendAssumeCapacity(@intCast(i));
    var out: std.ArrayList(u32) = try .initCapacity(arena.allocator(), size);

    const autobahn: Autobahn(u32, u32) = .{ .pool = &pool, .wg = &wg };
    try autobahn.mapAllocate(
        in.items,
        &out,
        .{ .allocator = arena.allocator(), .lane_count = 4, .lane_size = 1024 },
        copy,
        .{},
    );
}
```

## Usage with preallocated lanes

Using `Autobahn` is easy.
It's so small you can just copy and paste it into your project.

```zig
const std = @import("std");
const Autobahn = @import("autobahn").Autobahn;

pub fn main() !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();

    const lane_count = 4;
    const size = 400_000;
    const lane_size = 1024;

    var pool: std.Thread.Pool = undefined;
    try pool.init(std.Thread.Pool.Options{ .allocator = arena.allocator(), .n_jobs = lane_count });
    var wg = std.Thread.WaitGroup{};

    var in: std.ArrayList(u32) = try .initCapacity(arena.allocator(), size);
    for (0..in.capacity) |i| in.appendAssumeCapacity(@intCast(i));
    var out: std.ArrayList(u32) = try .initCapacity(arena.allocator(), size);

    var lanes: []std.ArrayList(u32) = undefined;
    lanes = try arena.allocator().alloc(std.ArrayList(u32), lane_count);
    for (0..lane_count) |i| lanes[i] = try .initCapacity(arena.allocator(), lane_size);

    const autobahn: Autobahn(u32, u32) = .{ .pool = &pool, .wg = &wg };
    autobahn.map(in.items, &out, &lanes, copy, .{});
}
```
