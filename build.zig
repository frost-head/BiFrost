const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- Dependencies (resolved once, shared everywhere) ---

    const vulkan_headers = b.dependency("vulkan_headers", .{});
    const vulkan = b.dependency("vulkan_zig", .{
        .registry = vulkan_headers.path("registry/vk.xml"),
    }).module("vulkan-zig");

    const zglfw = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
        .import_vulkan = true,
    });

    zglfw.module("root").addImport("vulkan", vulkan);
    // --- Library module: src/root.zig (the ONE source of truth) ---
    const lib_mod = b.addModule("BiFrost", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.addImport("vulkan", vulkan);
    lib_mod.addImport("zglfw", zglfw.module("root"));
    if (target.result.os.tag != .emscripten) {
        lib_mod.linkLibrary(zglfw.artifact("glfw"));
    }

    const lib = b.addLibrary(.{
        .name = "BiFrost",
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    // --- Executable: src/main.zig, imports the SAME lib_mod instance ---
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "BiFrost", .module = lib_mod },
            .{ .name = "zglfw", .module = zglfw.module("root") }, // convenient if main.zig also calls glfw directly
        },
    });

    const exe = b.addExecutable(.{
        .name = "BiFrost",
        .root_module = exe_mod,
    });
    if (target.result.os.tag != .emscripten) {
        exe.root_module.linkLibrary(zglfw.artifact("glfw"));
    }
    b.installArtifact(exe);

    // --- Run step ---
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    // --- Tests: one for the library module, one for the exe module ---
    const lib_tests = b.addTest(.{ .root_module = lib_mod });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    const exe_tests = b.addTest(.{ .root_module = exe_mod });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
