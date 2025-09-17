const std = @import("std");
const ztracy = @import("ztracy");
const autobahn = @import("autobahn");
const SpinningThreadPool = autobahn.SpinningThreadPool;

const AddEvenArgs = struct {
    input: []const i32,
    output: []i32,
    metadata: []usize,
    chunk_i: usize,
};

fn addEven(ctx: *anyopaque) void {
    const args: *AddEvenArgs = @ptrCast(@alignCast(ctx));
    var i: usize = 0;
    for (args.input) |x| {
        if (@mod(x, 2) == 0) {
            args.output[i] = x;
            i += 1;
        }
    }
    args.metadata[args.chunk_i] = i;
}

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{ .enable_memory_limit = true }) = .init;
    defer _ = gpa.deinit();
    const gpa_alloc = gpa.allocator();

    var arena: std.heap.ArenaAllocator = .init(gpa_alloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    const threads: usize = std.Thread.getCpuCount() catch 1;
    const workers = if (threads < 3) threads else threads - 1;
    var pool = try SpinningThreadPool.init(allocator, workers);
    defer pool.stop();

    const count: usize = 1_000_000;
    var input = try allocator.alloc(i32, count);
    for (0..count) |i| input[i] = @intCast(i);

    const chunk_size = 1_000;
    const chunks = @divFloor(input.len, chunk_size);
    var output = try allocator.alloc(i32, count + chunks);
    for (0..output.len) |i| output[i] = 0;

    const metadata: []usize = try allocator.alloc(usize, chunks);

    var args_list: std.ArrayList(AddEvenArgs) = .empty;

    var start: usize = 0;
    var end: usize = 0;

    var chunk_i: usize = 0;
    while (end < count) {
        end = @min(start + chunk_size, count);

        try args_list.append(
            allocator,
            .{
                .input = input[start..end],
                .output = output,
                .metadata = metadata,
                .chunk_i = chunk_i,
            },
        );

        const args_i: usize = args_list.items.len - 1;
        _ = pool.spawn(addEven, &args_list.items[args_i]);

        start = end;
        chunk_i += 1;
    }

    // wait for the rest to finish
    pool.waitAll();

    var filtered: std.ArrayList(i32) = .empty;

    for (args_list.items) |args| {
        const slice_start = args.chunk_i * chunk_size;
        const slice_len = metadata[args.chunk_i];
        const slice_end = slice_start + slice_len;
        try filtered.appendSlice(allocator, output[slice_start..slice_end]);
    }

    std.log.debug("Ran our filter function on {} values", .{count});
    try std.testing.expectEqual(@divFloor(count, 2), filtered.items.len);
    std.log.debug("Filtering was successful", .{});
}
