const std = @import("std");
const builtin = @import("builtin");

const ExampleData = struct {
    name: []const u8,
    source: []const u8,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const mod = b.addModule("autobahn", .{ .root_source_file = b.path("src/root.zig"), .target = target });

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    const ztracy_dep = b.dependency("ztracy", .{
        .enable_ztracy = b.option(bool, "enable_ztracy", "Enable Tracy profile markers") orelse false,
        .enable_fibers = b.option(bool, "enable_fibers", "Enable Tracy fiber support") orelse false,
        .on_demand = b.option(bool, "on_demand", "Build tracy with TRACY_ON_DEMAND") orelse false,
    });
    const ztracy_mod = ztracy_dep.module("root");

    // ======================
    // ==> EXAMPLE BUILDS <==
    // ======================
    for (&[_]ExampleData{
        .{ .name = "in_place", .source = "examples/in_place.zig" },
        .{ .name = "map", .source = "examples/map.zig" },
        .{ .name = "filter", .source = "examples/filter.zig" },
        .{ .name = "swap", .source = "examples/swap.zig" },
        // .{ .name = "pthread", .source = "examples/pthread.zig" },
    }) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.source),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "autobahn", .module = mod }},
            }),
        });
        exe.linkLibrary(ztracy_dep.artifact("tracy"));
        exe.root_module.addImport("ztracy", ztracy_mod);
        b.installArtifact(exe);

        const description: []const u8 = try std.fmt.allocPrint(allocator, "Run '{s}' example.", .{example.name});
        const run_name: []const u8 = try std.fmt.allocPrint(allocator, "run_{s}", .{example.name});
        const run_step = b.step(run_name, description);

        const run_cmd = b.addRunArtifact(exe);
        run_step.dependOn(&run_cmd.step);

        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
    }

    // =================================
    // ==> EMSCRIPTEN EXAMPLE BUILDS <==
    // =================================
    // {
    //     const zemscripten = @import("zemscripten");
    //     const web_run_step = b.step("web", "Run web build.");
    //     const wasm = b.addLibrary(
    //         .{
    //             .name = "zigfried",
    //             .root_module = mod,
    //         },
    //     );
    //     wasm.shared_memory = true;
    //     wasm.root_module.single_threaded = false;
    //     wasm.root_module.addImport("autobahn", mod);
    //
    //     const install_dir: std.Build.InstallDir = .{ .custom = "web" };
    //
    //     var emcc_flags = zemscripten.emccDefaultFlags(allocator, .{
    //         .optimize = optimize,
    //         .fsanitize = true,
    //     });
    //
    //     try emcc_flags.put("-sASYNCIFY", {});
    //     try emcc_flags.put("-sFULL-ES3=1", {});
    //     try emcc_flags.put("-sUSE_GLFW=3", {});
    //     try emcc_flags.put("-sUSE_OFFSET_CONVERTER", {});
    //     try emcc_flags.put("-sTOTAL_MEMORY=3072MB", {});
    //     try emcc_flags.put("-pthread", {});
    //     try emcc_flags.put("-sPTHREAD_POOL_SIZE=navigator.hardwareConcurrency", {});
    //     try emcc_flags.put("-sPROXY_TO_PTHREAD", {});
    //     try emcc_flags.put("-sOFFSCREEN_FRAMEBUFFER=1", {});
    //     try emcc_flags.put("-sASSERTIONS", {});
    //
    //     const emcc_settings = zemscripten.emccDefaultSettings(allocator, .{
    //         .optimize = optimize,
    //         .emsdk_allocator = std.heap.c_allocator,
    //     });
    //
    //     const emcc_step = blk: {
    //         const activate_emsdk_step = zemscripten.activateEmsdkStep(b);
    //
    //         const emsdk_dep = b.dependency("emsdk", .{});
    //         wasm.root_module.addIncludePath(emsdk_dep.path("upstream/emscripten/cache/sysroot/include"));
    //
    //         const emcc_step = zemscripten.emccStep(b, wasm, .{
    //             .optimize = optimize,
    //             .flags = emcc_flags,
    //             .settings = emcc_settings,
    //             .shell_file_path = b.path("shell-files/index.html"),
    //             .install_dir = install_dir,
    //             .embed_paths = &.{.{ .src_path = "assets/" }},
    //         });
    //         emcc_step.dependOn(activate_emsdk_step);
    //
    //         break :blk emcc_step;
    //     };
    //
    //     const html_filename = try std.fmt.allocPrint(b.allocator, "{s}.html", .{wasm.name});
    //     const emrun_step = zemscripten.emrunStep(
    //         b,
    //         b.getInstallPath(install_dir, html_filename),
    //         &.{},
    //     );
    //     emrun_step.dependOn(emcc_step);
    //     web_run_step.dependOn(emrun_step);
    // }
}
