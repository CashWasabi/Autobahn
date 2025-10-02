const std = @import("std");
const builtin = @import("builtin");
const emscripten = @import("emscripten.zig");

pub const Pool = @import("threading.zig").SpinningThreadPool;

pub fn getCpuCount() usize {
    switch (builtin.os.tag) {
        .wasm => emscripten.emscriptenGetCpuCount(),
        else => std.Thread.getCpuCount() catch 1,
    }
}
