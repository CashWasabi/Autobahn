const std = @import("std");
const emscripten = std.os.emscripten;

pub fn emscriptenGetCpuCount() c_int {
    return emscripten.emscripten_run_script_int(
        \\(function() {
        \\if (typeof navigator !== 'undefined' && navigator.hardwareConcurrency) {
        \\  return navigator.hardwareConcurrency;
        \\}
        \\return 1;
        \\})()
    );
}
