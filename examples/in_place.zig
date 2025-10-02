const std = @import("std");
const ztracy = @import("ztracy");
const autobahn = @import("autobahn");
const SpinningThreadPool = autobahn.SpinningThreadPool;

const Times2Args = struct { slice: []i32 };

fn times2(ctx: *anyopaque) void {
    const args: *Times2Args = @ptrCast(@alignCast(ctx));
    for (args.slice, 0..) |x, i| {
        args.slice[i] = x * 2;
    }
}

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{ .enable_memory_limit = true }) = .init;
    defer _ = gpa.deinit();
    const gpa_alloc = gpa.allocator();

    var arena: std.heap.ArenaAllocator = .init(gpa_alloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    const threads = std.Thread.getCpuCount() catch 1;
    const workers = if (threads < 3) threads else threads - 1;
    var pool = try SpinningThreadPool.init(allocator, workers);
    defer pool.stop();

    const count: usize = 1_000_000;
    var input = try allocator.alloc(i32, count);
    for (0..count) |i| input[i] = @intCast(i);
    var expected = try allocator.alloc(i32, count);
    for (0..count) |i| expected[i] = input[i] * 2;

    const chunk = 256;
    var args_list: std.ArrayList(Times2Args) = .empty;

    // split work into 3 chunks and spawn them

    var start: usize = 0;
    var end: usize = 0;
    while (end < count) {
        end = @min(start + chunk, count);

        try args_list.append(
            allocator,
            .{ .slice = input[start..end] },
        );
        _ = pool.spawn(times2, &args_list.items[args_list.items.len - 1]);

        start = end;
    }

    pool.waitAll();

    std.log.debug("Ran our map function on {}", .{count});
    try std.testing.expectEqualSlices(i32, expected, input);
    std.log.debug("Checking equality was successful", .{});
}
