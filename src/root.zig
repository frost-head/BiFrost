const glfw = @import("zglfw");
const Vlk = @import("vlk.zig");
const std = @import("std");

// Struct fields of this file
window: *glfw.Window = undefined,
Vulk: Vlk = Vlk{},

// Pass a pointer to the current instance to modify it
pub fn initWindow(self: *@This()) !void {
    try glfw.init();
    glfw.windowHint(.client_api, .no_api);
    self.window = try glfw.Window.create(800, 600, "BiFrost", null, null);
}

pub fn deinitEngine(self: *@This(), allocator: std.mem.Allocator) void {
    self.Vulk.deinit(allocator);
    self.window.destroy();
    glfw.terminate();
}

pub fn initVulkan(self: *@This(), allocator: std.mem.Allocator) !void {
    const glfwExtensions = try glfw.getRequiredInstanceExtensions();
    try self.Vulk.init(glfwExtensions, allocator);
    try self.Vulk.createSurface(self.window);
    try self.Vulk.pickPhysicalDevice(allocator);
    try self.Vulk.createLogicalDevice(allocator);
    try self.Vulk.createSwapChain(self.window, allocator);
    try self.Vulk.createImageViews(allocator);
}
pub fn mainLoop(self: *@This()) !void {
    while (!glfw.windowShouldClose(self.window)) {
        glfw.pollEvents();
    }
}

pub fn run(self: *@This(), allocator: std.mem.Allocator) !void {
    try self.initWindow();
    try self.initVulkan(allocator);
    errdefer self.deinitEngine(allocator);
    try self.mainLoop();
}
