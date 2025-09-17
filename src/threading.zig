const std = @import("std");

pub const SpinningThreadPool = struct {
    pub const TaskFn = *const fn (*anyopaque) void;

    const Task = struct {
        func: TaskFn,
        ctx: *anyopaque,
    };

    const WorkerHandle = struct {
        id: usize,
        iteration: usize,
    };

    const Worker = struct {
        thread: std.Thread,
        task: ?Task = null,
        iteration: std.atomic.Value(usize) = .init(0),
        state: std.atomic.Value(u8) = .init(0), // 0=idle, 1=running, 2=stop

        fn loop(self: *Worker) void {
            while (true) {
                switch (self.state.load(.monotonic)) {
                    0 => std.atomic.spinLoopHint(), // idle
                    1 => {
                        if (self.task) |t| t.func(t.ctx);
                        self.task = null;
                        self.state.store(0, .monotonic);
                        _ = self.iteration.fetchAdd(1, .monotonic);
                    },
                    2 => return, // stop
                    else => {},
                }
            }
        }
    };

    workers: []Worker,

    pub fn init(allocator: std.mem.Allocator, n: usize) !SpinningThreadPool {
        const workers = try allocator.alloc(Worker, n);
        for (workers) |*w| {
            w.* = .{
                .thread = try std.Thread.spawn(.{}, Worker.loop, .{w}),
                .task = null,
            };
        }
        return .{ .workers = workers };
    }

    /// Pick next free worker and assign a task
    pub fn spawn(pool: *SpinningThreadPool, func: TaskFn, ctx: *anyopaque) WorkerHandle {
        while (true) {
            for (pool.workers, 0..) |*w, i| {
                if (w.state.load(.monotonic) == 0) {
                    w.task = .{ .func = func, .ctx = ctx };
                    w.state.store(1, .monotonic); // running
                    return .{ .id = i, .iteration = w.iteration.load(.monotonic) };
                }
            }
            std.atomic.spinLoopHint();
        }
    }

    /// Block until all workers are idle
    pub fn waitAll(pool: *SpinningThreadPool) void {
        while (true) {
            var all_idle = true;
            for (pool.workers) |*w| {
                if (w.state.load(.monotonic) != 0) {
                    all_idle = false;
                    break;
                }
            }
            if (all_idle) break;
            std.atomic.spinLoopHint();
        }
    }

    pub fn stop(pool: *SpinningThreadPool) void {
        for (pool.workers) |*w| {
            w.state.store(2, .monotonic);
        }
        for (pool.workers) |*w| {
            _ = w.thread.join();
        }
    }
};

// Example with arguments
const Times2Args = struct {
    input: []const i32,
    output: []i32,
};

fn times2(ctx: *anyopaque) void {
    const args: *Times2Args = @ptrCast(@alignCast(ctx));
    for (args.input, 0..) |x, i| {
        args.output[i] = x * 2;
    }
}

test "spin pool" {
    var gpa: std.heap.DebugAllocator(.{ .enable_memory_limit = true }) = .init;
    defer _ = gpa.deinit();
    const gpa_alloc = gpa.allocator();

    var arena: std.heap.ArenaAllocator = .init(gpa_alloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    var pool = try SpinningThreadPool.init(allocator, 3);
    defer pool.stop();

    const count: usize = 1_000_000;
    var input = try allocator.alloc(i32, count);
    for (0..count) |i| input[i] = @intCast(i);
    var expected = try allocator.alloc(i32, count);
    for (0..count) |i| expected[i] = input[i] * 2;
    var output = try allocator.alloc(i32, count);
    for (0..count) |i| output[i] = 0;

    const chunk = 2;
    var args_list: std.ArrayList(Times2Args) = .empty;

    // split work into 3 chunks and spawn them

    var start: usize = 0;
    var end: usize = 0;
    while (end < count) {
        end = @min(start + chunk, count);

        try args_list.append(
            allocator,
            .{ .input = input[start..end], .output = output[start..end] },
        );
        pool.spawn(times2, &args_list.items[args_list.items.len - 1]);

        start = end;
    }

    pool.waitAll();

    try std.testing.expectEqualSlices(i32, expected, output);
}
