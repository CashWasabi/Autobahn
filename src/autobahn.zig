const std = @import("std");
const Pool = @import("threading.zig").SpinningThreadPool;

pub fn map(
    comptime I: type,
    comptime O: type,
    pool: *Pool,
    in: []I,
    out: []O,
    opts: struct { chunk_size: usize },
) void {
    _ = pool;
    _ = in;
    _ = out;
    _ = opts;
}

pub fn swap(
    comptime T: type,
    pool: *Pool,
    values: []T,
    opts: struct { chunk_size: usize },
) void {
    _ = pool;
    _ = values;
    _ = opts;
}

pub fn filter(
    comptime I: type,
    comptime O: type,
    pool: *Pool,
    in: []I,
    out: []O,
    opts: struct { chunk_size: usize },
) void {
    _ = pool;
    _ = in;
    _ = out;
    _ = opts;
}
