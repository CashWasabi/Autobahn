pub fn Autobahn(comptime I: type, comptime O: type) type {
    return struct {
        const Self = @This();
        const LaneFunc = fn (lane: usize, in: []I, out: *std.ArrayList(O)) void;
        const Options = struct { lanes: usize, lane_capacity: usize };

        lanes: []std.ArrayList(O),

        pub fn initCapacity(allocator: std.mem.Allocator, opts: Options) !Self {
            std.debug.assert(opts.lanes > 0);
            std.debug.assert(opts.lane_capacity > 0);
            std.debug.assert(opts.lane_capacity >= opts.lanes);

            var lanes: []std.ArrayList(O) = undefined;
            const remainder: usize = @rem(opts.lane_capacity, opts.lanes);
            if (remainder == 0) {
                lanes = try allocator.alloc(std.ArrayList(O), opts.lanes);
                const lane_size = @divFloor(opts.lane_capacity, opts.lanes);
                for (0..opts.lanes) |i| lanes[i] = try .initCapacity(allocator, lane_size);
            } else {
                lanes = try allocator.alloc(std.ArrayList(O), opts.lanes);
                const lane_size: usize = @divFloor(opts.lane_capacity, opts.lanes);
                lanes[0] = try .initCapacity(allocator, lane_size + remainder);
                for (1..opts.lanes) |i| lanes[i] = try .initCapacity(allocator, lane_size);
            }

            return .{ .lanes = lanes };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            for (self.lanes) |*lane| lane.deinit(allocator);
            allocator.free(self.lanes);
        }

        pub fn forEach(self: *Self, worker_func: LaneFunc, in: []I, out: *std.ArrayList(O)) void {
            // Single-thread fallback
            if (self.lanes.len == 1) {
                worker_func(1, in, out);
                return;
            }

            for (self.lanes) |*lane| lane.clearRetainingCapacity();
            const chunk_size = (in.len + self.lanes.len - 1) / self.lanes.len;

            var wg = std.Thread.WaitGroup{};
            wg.reset();

            for (self.lanes, 0..) |*lane, i| {
                const start = i * chunk_size;
                const end = @min(start + chunk_size, in.len);

                wg.spawnManager(worker_func, .{ i, in[start..end], lane });
            }

            wg.wait();

            for (self.lanes) |lane| out.appendSliceAssumeCapacity(lane.items);
        }
    };
}

const std = @import("std");
const Pool = std.Thread.Pool;
const WaitGroup = std.Thread.WaitGroup;

fn testLaneFunc(lane: usize, in: []u32, out: *std.ArrayList(u32)) void {
    _ = lane;
    out.appendSliceAssumeCapacity(in);
}

const Driver = struct { lane: usize, id: u32 };

fn sortById(_: void, lhs: Driver, rhs: Driver) bool {
    return lhs.id == rhs.id;
}

fn testStructLaneFunc(lane: usize, in: []u32, out: *std.ArrayList(Driver)) void {
    for (in) |id| out.appendAssumeCapacity(.{ .lane = lane, .id = id });
}

test "autobahn single threaded u32" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();

    const size: usize = 1_000_000;

    var in: std.ArrayList(u32) = try .initCapacity(arena.allocator(), size);
    var out: std.ArrayList(u32) = try .initCapacity(arena.allocator(), size);
    var expected_out: std.ArrayList(u32) = try .initCapacity(arena.allocator(), size);
    for (0..size) |i| {
        const value: u32 = @intCast(i);
        in.appendAssumeCapacity(value);
        expected_out.appendAssumeCapacity(value);
    }

    var map: Autobahn(u32, u32) = try .initCapacity(std.testing.allocator, .{ .lanes = 1, .lane_capacity = size });
    map.forEach(testLaneFunc, in.items, &out);
    map.deinit(std.testing.allocator);

    std.mem.sort(u32, out.items, {}, comptime std.sort.asc(u32));

    try std.testing.expectEqual(expected_out.items.len, out.items.len);
    try std.testing.expectEqualSlices(u32, expected_out.items, out.items);
}

test "autobahn multi threaded u32" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();

    const cpu_count = std.Thread.getCpuCount() catch 1;
    const thread_count = if (cpu_count > 1) cpu_count else 1;

    const size: usize = 1_000_000;

    var in: std.ArrayList(u32) = try .initCapacity(arena.allocator(), size);
    var out: std.ArrayList(u32) = try .initCapacity(arena.allocator(), size);
    var expected_out: std.ArrayList(u32) = try .initCapacity(arena.allocator(), size);
    for (0..size) |i| {
        const value: u32 = @intCast(i);
        in.appendAssumeCapacity(value);
        expected_out.appendAssumeCapacity(value);
    }

    var map: Autobahn(u32, u32) = try .initCapacity(std.testing.allocator, .{ .lanes = thread_count, .lane_capacity = size });
    map.forEach(testLaneFunc, in.items, &out);
    map.deinit(std.testing.allocator);

    std.mem.sort(u32, out.items, {}, comptime std.sort.asc(u32));

    try std.testing.expectEqual(expected_out.items.len, out.items.len);
    try std.testing.expectEqualSlices(u32, expected_out.items, out.items);
}

test "autobahn multi threaded Driver" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
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
        expected_out.appendAssumeCapacity(.{ .lane = 0, .id = value });
    }

    var map: Autobahn(u32, Driver) = try .initCapacity(std.testing.allocator, .{ .lanes = thread_count, .lane_capacity = size });
    map.forEach(testStructLaneFunc, in.items, &out);
    map.deinit(std.testing.allocator);

    std.mem.sort(Driver, out.items, {}, sortById);

    try std.testing.expectEqual(expected_out.items.len, out.items.len);
    for (0..expected_out.items.len) |i| {
        try std.testing.expectEqual(expected_out.items[i].id, out.items[i].id);
    }
}

test "autobahn multi threaded smol" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();

    const cpu_count = std.Thread.getCpuCount() catch 1;
    const thread_count = if (cpu_count > 1) cpu_count else 1;

    const size: usize = 10;

    var in: std.ArrayList(u32) = try .initCapacity(arena.allocator(), size);
    var out: std.ArrayList(Driver) = try .initCapacity(arena.allocator(), size);
    var expected_out: std.ArrayList(Driver) = try .initCapacity(arena.allocator(), size);
    for (0..size) |i| {
        const value: u32 = @intCast(i);
        in.appendAssumeCapacity(value);
        expected_out.appendAssumeCapacity(.{ .lane = 0, .id = value });
    }

    var map: Autobahn(u32, Driver) = try .initCapacity(std.testing.allocator, .{ .lanes = thread_count, .lane_capacity = size });
    map.forEach(testStructLaneFunc, in.items, &out);
    map.deinit(std.testing.allocator);

    std.mem.sort(Driver, out.items, {}, sortById);

    try std.testing.expectEqual(expected_out.items.len, out.items.len);
    for (0..expected_out.items.len) |i| {
        try std.testing.expectEqual(expected_out.items[i].id, out.items[i].id);
    }
}
