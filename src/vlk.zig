const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("zglfw");
const builtin = @import("builtin");

const BaseWrapper = vk.BaseWrapper;
const InstanceWrapper = vk.InstanceWrapper;
const enable_vaildation = builtin.mode == .Debug;
const validation_layer = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};

const Self = @This();

vkb: BaseWrapper = undefined,
vki: InstanceWrapper = undefined,
instance: vk.Instance = undefined,
initialized: bool = false,

pub fn init(self: *Self, extensions: [][*:0]const u8, allocator: std.mem.Allocator) !void {
    self.vkb = BaseWrapper.load(glfw.getInstanceProcAddress);

    if (enable_vaildation) {
        if (!try self.check_validation_support(allocator)) {
            return error.VkValidationLayerNotFound;
        }
    }

    const app_info = vk.ApplicationInfo{
        .p_application_name = "BiFrost",
        .application_version = vk.makeApiVersion(0, 1, 0, 0).toU32(),
        .p_engine_name = "No Engine",
        .engine_version = vk.makeApiVersion(0, 1, 0, 0).toU32(),
        .api_version = vk.API_VERSION_1_4.toU32(),
    };
    var extension_list: std.ArrayList([*:0]const u8) = .empty;
    try extension_list.appendSlice(allocator, extensions);
    try extension_list.append(allocator, vk.extensions.khr_portability_enumeration.name);
    defer extension_list.deinit(allocator);

    const create_info = vk.InstanceCreateInfo{
        .p_application_info = &app_info,
        .enabled_extension_count = @intCast(extension_list.items.len),
        .pp_enabled_extension_names = extension_list.items.ptr,
        .flags = .{ .enumerate_portability_bit_khr = true },
        .enabled_layer_count = if (enable_vaildation) validation_layer.len else 0,
        .pp_enabled_layer_names = if (enable_vaildation) &validation_layer else null,
    };

    self.instance = try self.vkb.createInstance(&create_info, null);
    self.vki = InstanceWrapper.load(self.instance, self.vkb.dispatch.vkGetInstanceProcAddr.?);
    self.initialized = true;
}

pub fn deinit(self: *Self) void {
    if (!self.initialized) return;
    self.vki.destroyInstance(self.instance, null);
    self.initialized = false;
}

pub fn check_validation_support(self: *Self, allocator: std.mem.Allocator) !bool {
    var layer_count: u32 = undefined;
    _ = try self.vkb.enumerateInstanceLayerProperties(&layer_count, null);

    const available_layers = try allocator.alloc(vk.LayerProperties, layer_count);
    defer allocator.free(available_layers);
    _ = try self.vkb.enumerateInstanceLayerProperties(&layer_count, available_layers.ptr);

    for (validation_layer) |wanted| {
        var found = false;
        for (available_layers) |layer| {
            const name_len = std.mem.indexOfScalar(u8, &layer.layer_name, 0) orelse layer.layer_name.len;
            if (std.mem.eql(u8, layer.layer_name[0..name_len], std.mem.span(wanted))) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

pub fn pick_physical_device(self: *Self, allocator: std.mem.Allocator) !void {
    var device_count: u32 = undefined;
    _ = try self.vki.enumeratePhysicalDevices(self.instance, &device_count, null);

    if (device_count == 0) {
        std.debug.print("Failed to find Vulkan supported GPUs\n", .{});
        return error.FailedToFindVulaknSupportGPUs;
    }

    const available_devices = try allocator.alloc(vk.PhysicalDevice, device_count);
    defer allocator.free(available_devices);

    _ = try self.vki.enumeratePhysicalDevices(self.instance, &device_count, available_devices.ptr);

    std.debug.print("following devices are available : {any}\n", .{available_devices});
    var pDevice: vk.PhysicalDevice = undefined;
    for (available_devices[0..device_count]) |device| {
        if (self.isDeviceSuitable(device, allocator)) {
            pDevice = device;
            break;
        }
    }
    if (pDevice == vk.PhysicalDevice.null_handle) {
        std.debug.print("failed to find a suitable GPU!\n", .{});
        return error.NoSuitableGPUFound;
    }
    std.debug.print("selected GPU : {}\n", .{pDevice});
}

pub fn isDeviceSuitable(self: *Self, device: vk.PhysicalDevice, allocator: std.mem.Allocator) bool {
    const indicies = self.findQueueFamilyIndices(device, allocator) catch |err| {
        std.debug.print("Encountred {} while trying to get queue indices for {}, rejecting device as unsuitable", .{ err, device });
        return false;
    };

    return indicies.is_complete();
}

const QueueFamilyIndices = struct {
    graphics_index: ?u32,

    pub fn is_complete(self: @This()) bool {
        if (self.graphics_index) |ind| {
            _ = ind;
            return true;
        } else {
            return false;
        }
    }
};

pub fn findQueueFamilyIndices(self: *Self, physical_device: vk.PhysicalDevice, allocator: std.mem.Allocator) !QueueFamilyIndices {
    var queueCount: u32 = undefined;
    _ = self.vki.getPhysicalDeviceQueueFamilyProperties(physical_device, &queueCount, null);

    const available_queues = try allocator.alloc(vk.QueueFamilyProperties, queueCount);
    defer allocator.free(available_queues);

    _ = self.vki.getPhysicalDeviceQueueFamilyProperties(physical_device, &queueCount, available_queues.ptr);

    const graphics_index = get_graphics_queue_index(available_queues, queueCount);
    return QueueFamilyIndices{ .graphics_index = graphics_index };
}

fn get_graphics_queue_index(available_queues: []vk.QueueFamilyProperties, queueCount: u32) ?u32 {
    for (available_queues[0..queueCount], 0..) |*queue, ind| {
        const index: u32 = @intCast(ind);
        if (queue.queue_flags.graphics_bit) return index;
    }
    return null;
}
