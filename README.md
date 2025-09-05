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

## Usage

Using `Autobahn` is easy.
It's so small you can just copy and paste it into your project.

```zig
const std = @import("std");
const Autobahn = @import("autobahn").Autobahn;

const Driver = struct {
    id: u32,
    lane: usize = 0,
};

pub fn lane(lane: usize, in: []u32, out: []Driver) void {
    for (in) |id| out.appendAssumeCapacity(.{ .lane = thread_id, .id = id });
}

pub fn main() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();

    const cpu_count = std.Thread.getCpuCount() catch 1;
    const thread_count = if (cpu_count > 1) cpu_count else 1;

    const size: usize = 1_000_000;

    var in: std.ArrayList(u32) = try .initCapacity(arena.allocator(), size);
    var out: std.ArrayList(Driver) = try .initCapacity(arena.allocator(), size);
    var expected_out: std.ArrayList(Driver) = try .initCapacity(arena.allocator(), size);
    for (0..size) |i| {
        const value: u32 = @intCast(i);
        in.appendAssumeCapacity(value);
        expected_out.appendAssumeCapacity(.{ .id = value });
    }

    var map: Autobahn(u32, Driver) = try .initCapacity(arena, .{ .lanes = thread_count, .lane_capacity = size });
    map.forEach(lane, in.items, &out, .{});
}
```
