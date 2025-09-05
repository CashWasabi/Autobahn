const std = @import("std");
const Pool = std.Thread.Pool;
const WaitGroup = std.Thread.WaitGroup;

pub fn Autobahn(comptime O: type) type {
    return struct {
        const Self = @This();

        pool: *std.Thread.Pool,
        wg: *std.Thread.WaitGroup,

        pub fn init(pool: *std.Thread.Pool, wg: *std.Thread.WaitGroup) Self {
            return .{ .pool = pool, .wg = wg };
        }

        pub fn forEach(
            self: Self,
            lanes: *[]std.ArrayList(O),
            out: *std.ArrayList(O),
            comptime lane_func: anytype,
            args: anytype,
        ) void {
            self.wg.reset();

            var start: usize = 0;
            for (lanes.*) |*lane| {
                const end = start + lane.capacity;
                self.pool.spawnWg(self.wg, lane_func, args ++ .{ start, end, lane });
                start += lane.capacity;
            }

            self.wg.wait();

            for (lanes.*) |lane| out.appendSliceAssumeCapacity(lane.items);
        }
    };
}

fn copy(in: []u32, start: usize, end: usize, out: *std.ArrayList(u32)) void {
    for (in[start..end]) |item| out.appendAssumeCapacity(item);
}

test "pool and wait group autobahn" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();

    const lane_count = 4;
    const size = 400_000;
    const lane_size = @divFloor(size, lane_count);

    var pool: std.Thread.Pool = undefined;
    try pool.init(std.Thread.Pool.Options{ .allocator = arena.allocator(), .n_jobs = lane_count });
    var wg = std.Thread.WaitGroup{};

    var in: std.ArrayList(u32) = try .initCapacity(arena.allocator(), size);
    for (0..in.capacity) |i| in.appendAssumeCapacity(@intCast(i));
    var out: std.ArrayList(u32) = try .initCapacity(arena.allocator(), size);

    var lanes: []std.ArrayList(u32) = undefined;
    lanes = try arena.allocator().alloc(std.ArrayList(u32), lane_count);
    for (0..lane_count) |i| lanes[i] = try .initCapacity(arena.allocator(), lane_size);

    const autobahn: Autobahn(u32) = .{ .pool = &pool, .wg = &wg };
    autobahn.forEach(&lanes, &out, copy, .{in.items});

    std.mem.sort(u32, out.items, {}, comptime std.sort.asc(u32));
    try std.testing.expectEqual(in.items.len, out.items.len);
    try std.testing.expectEqualSlices(u32, in.items, out.items);
}
