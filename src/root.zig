const glfw = @import("zglfw");
const vlk = @import("vlk.zig");
const std = @import("std");

// Struct fields of this file
window: *glfw.Window = undefined,
vulk: vlk = vlk{},

// Pass a pointer to the current instance to modify it
pub fn initWindow(self: *@This()) !void {
    try glfw.init();
    self.window = try glfw.Window.create(800, 600, "BiFrost", null, null);
}

pub fn deinitEngine(self: *@This()) void {
    self.vulk.deinit();
    self.window.destroy();
    glfw.terminate();
}

pub fn initVulkan(self: *@This(), allocator: std.mem.Allocator) !void {
    const glfwExtensions = try glfw.getRequiredInstanceExtensions();
    try self.vulk.init(glfwExtensions, allocator);
    try self.vulk.pick_physical_device(allocator);
}
pub fn mainLoop(self: *@This()) !void {
    while (!glfw.windowShouldClose(self.window)) {
        glfw.pollEvents();
    }
}

pub fn run(self: *@This(), allocator: std.mem.Allocator) !void {
    try self.initWindow();
    try self.initVulkan(allocator);
    errdefer self.deinitEngine();
    try self.mainLoop();
}
