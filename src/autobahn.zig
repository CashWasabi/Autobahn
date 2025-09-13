const std = @import("std");
const Pool = std.Thread.Pool;
const WaitGroup = std.Thread.WaitGroup;

pub fn Autobahn(comptime I: type, comptime O: type) type {
    return struct {
        const Self = @This();

        pool: *std.Thread.Pool,
        wg: *std.Thread.WaitGroup,

        pub fn init(pool: *std.Thread.Pool, wg: *std.Thread.WaitGroup) Self {
            return .{ .pool = pool, .wg = wg };
        }

        pub const MapAllocateOptions = struct {
            allocator: std.mem.Allocator,
            lane_count: usize,
            lane_size: usize,
        };

        pub fn map(
            self: Self,
            in: []I,
            out: *std.ArrayList(O),
            lanes: *[]std.ArrayList(O),
            comptime lane_func: anytype,
            args: anytype,
        ) void {
            std.debug.assert(lanes.len > 0);
            var total_lane_capacity: usize = 0;
            for (lanes.*) |lane| total_lane_capacity += lane.capacity;
            std.debug.assert(total_lane_capacity > 0);

            // TODO: add single threaded check
            if (lanes.len == 1) {
                @call(.auto, lane_func, .{ in[0..], out } ++ args);
                return;
            }

            var start: usize = 0;
            var end: usize = 0;
            while (end < in.len) {
                self.wg.reset();

                for (lanes.*) |*lane| {
                    lane.clearRetainingCapacity();

                    end = @min(start + lane.capacity, in.len);
                    self.pool.spawnWg(self.wg, lane_func, .{ in[start..end], lane } ++ args);
                    start = end;
                }

                self.wg.wait();

                for (lanes.*) |lane| out.appendSliceAssumeCapacity(lane.items);
            }
        }

        pub fn mapAllocate(
            self: Self,
            in: []I,
            out: *std.ArrayList(O),
            opts: MapAllocateOptions,
            comptime lane_func: anytype,
            args: anytype,
        ) !void {
            std.debug.assert(opts.lane_count > 0);
            std.debug.assert(opts.lane_size > 0);

            // TODO: add single threaded check
            if (opts.lane_count == 1) {
                @call(.auto, lane_func, .{ in[0..], out } ++ args);
                return;
            }

            var lanes: []std.ArrayList(O) = try opts.allocator.alloc(std.ArrayList(O), opts.lane_count);
            for (0..opts.lane_count) |i| lanes[i] = try .initCapacity(opts.allocator, opts.lane_size);
            defer {
                for (lanes) |*lane| lane.deinit(opts.allocator);
                opts.allocator.free(lanes);
            }

            var start: usize = 0;
            var end: usize = 0;
            while (end < in.len) {
                self.wg.reset();

                for (lanes) |*lane| {
                    lane.clearRetainingCapacity();

                    end = @min(start + lane.capacity, in.len);
                    self.pool.spawnWg(self.wg, lane_func, .{ in[start..end], lane } ++ args);
                    start = end;
                }

                self.wg.wait();

                for (lanes) |lane| out.appendSliceAssumeCapacity(lane.items);
            }
        }
    };
}

pub fn AutobahnManaged(comptime I: type, comptime O: type) type {
    return struct {
        const Self = @This();

        pool: *std.Thread.Pool,
        wg: *std.Thread.WaitGroup,
        lanes: []std.ArrayList(O),

        pub const LaneOptions = struct { lane_count: usize, lane_size: usize };

        pub fn init(allocator: std.mem.Allocator, pool: *std.Thread.Pool, wg: *std.Thread.WaitGroup, opts: LaneOptions) !Self {
            std.debug.assert(opts.lane_count > 0);
            std.debug.assert(opts.lane_size > 0);

            const lanes: []std.ArrayList(O) = try allocator.alloc(std.ArrayList(O), opts.lane_count);
            for (0..opts.lane_count) |i| lanes[i] = try .initCapacity(allocator, opts.lane_size);

            return .{ .pool = pool, .wg = wg, .lanes = lanes };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            for (self.lanes) |*lane| lane.deinit();
            allocator.free(self.lanes);
        }

        pub fn map(self: Self, in: []I, out: *std.ArrayList(O), comptime lane_func: anytype, args: anytype) void {
            if (self.lanes.len == 1) {
                @call(.auto, lane_func, .{ in[0..], out } ++ args);
                return;
            }

            var start: usize = 0;
            var end: usize = 0;
            while (end < in.len) {
                self.wg.reset();

                for (self.lanes) |*lane| {
                    lane.clearRetainingCapacity();

                    end = @min(start + lane.capacity, in.len);
                    self.pool.spawnWg(self.wg, lane_func, .{ in[start..end], lane } ++ args);
                    start = end;
                }

                self.wg.wait();

                for (self.lanes) |lane| out.appendSliceAssumeCapacity(lane.items);
            }
        }
    };
}

fn copy(in: []u32, lane: *std.ArrayList(u32)) void {
    for (in) |item| lane.appendAssumeCapacity(item);
}

test "pool and wait group autobahn lanes preallocated" {
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

    std.mem.sort(u32, out.items, {}, comptime std.sort.asc(u32));
    try std.testing.expectEqual(in.items.len, out.items.len);
    try std.testing.expectEqualSlices(u32, in.items, out.items);
}

test "pool and wait group autobahn lanes allocating" {
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

    std.mem.sort(u32, out.items, {}, comptime std.sort.asc(u32));
    try std.testing.expectEqual(in.items.len, out.items.len);
    try std.testing.expectEqualSlices(u32, in.items, out.items);
}
