// BiFrost - Vulkan presentation layer application
// ============================================================================
// Main entry point for the BiFrost application.
//
// The application initializes the graphics engine, runs its main loop,
// and gracefully shuts down all resources on exit.

const std = @import("std");
const root = @import("BiFrost");

/// Main entry point for the BiFrost application.
///
/// Initializes and runs the graphics engine with the provided process info,
/// ensuring proper resource cleanup via `defer`. The engine runs until the
/// window is closed, then destroys all Vulkan and GLFW resources.
///
/// @param init - std.process.Init containing application process info
///              (window title, argv, env vars for the child process)
pub fn main(init: std.process.Init) !void {
    var engine = root{};
    defer engine.deinitEngine(init.gpa);
    try engine.run(init.gpa);
}
