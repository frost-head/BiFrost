// Application Engine - Core state and lifecycle management
// ============================================================================
// The engine owns the GLFW window, Vulkan instance, logical device, and swap chain.
// It provides a simple API for creating the display window, initializing Vulkan,
// running the main loop, and cleaning up all resources.

const glfw = @import("zglfw");
const Vlk = @import("vlk.zig");
const std = @import("std");


/// Struct fields of this file
window: *glfw.Window = undefined,
Vulk: Vlk = Vlk{},


/// Pass a pointer to the current instance to modify it
pub fn initWindow(self: *@This()) !void {
    try glfw.init();
    glfw.windowHint(.client_api, .no_api);
    self.window = try glfw.Window.create(800, 600, "BiFrost", null, null);
}


/// Deinitialize all engine resources.
///
/// Frees the Vulkan instance and logical device, destroys swap chain images
/// and image views, closes the window, and terminates GLFW. Called via `defer`
/// in `run()` to ensure cleanup even when errors occur.
///
/// @param allocator - std.mem.Allocator for freeing Vulkan-managed memory
pub fn deinitEngine(self: *@This(), allocator: std.mem.Allocator) void {
    self.Vulk.deinit(allocator);
    self.window.destroy();
    glfw.terminate();
}


/// Initialize the Vulkan subsystem.
///
/// Creates the OpenGL surface, initializes Vulkan with the required GLFW
/// extensions, picks a suitable physical device, creates a logical device
/// with graphics and present queues, and sets up the swap chain.
///
/// @param allocator - std.mem.Allocator for Vulkan memory allocation
pub fn initVulkan(self: *@This(), allocator: std.mem.Allocator) !void {
    const glfwExtensions = try glfw.getRequiredInstanceExtensions();
    try self.Vulk.init(glfwExtensions, allocator);
    try self.Vulk.createSurface(self.window);
    try self.Vulk.pickPhysicalDevice(allocator);
    try self.Vulk.createLogicalDevice(allocator);
    try self.Vulk.createSwapChain(self.window, allocator);
    try self.Vulk.createImageViews(allocator);
}


/// Run the application's main loop.
///
/// Polls GLFW for window events and runs until the user closes the window.
/// Call this after `initWindow()` and `initVulkan()` have been called.
pub fn mainLoop(self: *@This()) !void {
    while (!glfw.windowShouldClose(self.window)) {
        glfw.pollEvents();
    }
}


/// Run the application lifecycle: initialize, loop, and clean up.
///
/// Orchestrates the full application flow:
/// 1. Creates and initializes the GLFW window (800x600 "BiFrost")
/// 2. Initializes Vulkan on the window's surface
/// 3. Runs the main event loop until window close
/// 4. Deinitializes engine resources via `errdefer`
///
/// @param allocator - std.mem.Allocator for Vulkan memory allocation.
///                  Must persist until the engine is fully deinitialized.
pub fn run(self: *@This(), allocator: std.mem.Allocator) !void {
    try self.initWindow();
    try self.initVulkan(allocator);
    errdefer self.deinitEngine(allocator);
    try self.mainLoop();
}
