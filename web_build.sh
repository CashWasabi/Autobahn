zig build run -Dtarget=wasm32-emscripten \
  -Dcpu=generic+atomics+bulk_memory+bulk_memory_opt+simd128
