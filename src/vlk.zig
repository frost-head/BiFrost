const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("zglfw");
const builtin = @import("builtin");

const Self = @This();

const QueueFamilyIndices = struct {
    graphicsFamily: ?u32,
    presentFamily: ?u32,

    pub fn is_complete(self: @This()) bool {
        return self.graphicsFamily != null and self.presentFamily != null;
    }
};

const BaseWrapper = vk.BaseWrapper;
const InstanceWrapper = vk.InstanceWrapper;
const DeviceWrapper = vk.DeviceWrapper;
const enable_vaildation = builtin.mode == .Debug;
const validation_layer = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};

vkb: BaseWrapper = undefined,
vki: InstanceWrapper = undefined,
vkd: DeviceWrapper = undefined,
instance: vk.Instance = undefined,
surface: vk.SurfaceKHR = undefined,
initialized: bool = false,
device: vk.Device = undefined,
physicalDevice: vk.PhysicalDevice = undefined,
graphics_queue: vk.Queue = undefined,
present_queue: vk.Queue = undefined,

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
    self.vkd.destroyDevice(self.device, null);
    self.vki.destroySurfaceKHR(self.instance, self.surface, null);
    if (!self.initialized) return;
    self.vki.destroyInstance(self.instance, null);
    self.initialized = false;
}

pub fn create_surface(self: *Self, window: *glfw.Window) !void {
    try glfw.createWindowSurface(self.instance, window, null, &self.surface);
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
    for (available_devices[0..device_count]) |physicalDevice| {
        if (self.isDeviceSuitable(physicalDevice, allocator)) {
            pDevice = physicalDevice;
            break;
        }
    }
    if (pDevice == vk.PhysicalDevice.null_handle) {
        std.debug.print("failed to find a suitable GPU!\n", .{});
        return error.NoSuitableGPUFound;
    }
    self.physicalDevice = pDevice;
    std.debug.print("selected GPU : {}\n", .{pDevice});
}

pub fn isDeviceSuitable(self: *Self, physicalDevice: vk.PhysicalDevice, allocator: std.mem.Allocator) bool {
    const indicies = self.findQueueFamilyIndices(physicalDevice, allocator) catch |err| {
        std.debug.print("Encountred {} while trying to get queue indices for {}, rejecting physical device as unsuitable", .{ err, physicalDevice });
        return false;
    };

    return indicies.is_complete();
}

pub fn findQueueFamilyIndices(self: *Self, physical_device: vk.PhysicalDevice, allocator: std.mem.Allocator) !QueueFamilyIndices {
    var queueCount: u32 = undefined;
    _ = self.vki.getPhysicalDeviceQueueFamilyProperties(physical_device, &queueCount, null);

    const available_queues = try allocator.alloc(vk.QueueFamilyProperties, queueCount);
    defer allocator.free(available_queues);

    _ = self.vki.getPhysicalDeviceQueueFamilyProperties(physical_device, &queueCount, available_queues.ptr);

    const graphicsFamily = get_graphics_queue_index(available_queues, queueCount);
    const presentFamily: ?u32 = get_present_queue_index(self, physical_device, available_queues, queueCount);
    return QueueFamilyIndices{ .graphicsFamily = graphicsFamily, .presentFamily = presentFamily };
}

fn get_graphics_queue_index(available_queues: []vk.QueueFamilyProperties, queueCount: u32) ?u32 {
    for (available_queues[0..queueCount], 0..) |*queue, ind| {
        const index: u32 = @intCast(ind);
        if (queue.queue_flags.graphics_bit) return index;
    }
    return null;
}

fn get_present_queue_index(self: *Self, physical_device: vk.PhysicalDevice, available_queues: []vk.QueueFamilyProperties, queueCount: u32) ?u32 {
    for (available_queues[0..queueCount], 0..) |_, ind| {
        const index: u32 = @intCast(ind);
        const present_support = self.vki.getPhysicalDeviceSurfaceSupportKHR(physical_device, index, self.surface) catch |err|
            {
                std.debug.print("Encountered error while checking surface support for device : {} - {}", .{ physical_device, err });
                continue;
            };
        if (present_support == .true) return index;
    }
    return null;
}

pub fn create_logical_device(self: *Self, allocator: std.mem.Allocator) !void {
    const indices = try self.findQueueFamilyIndices(self.physicalDevice, allocator);
    const queue_priorities = [_]f32{1.0};

    var unique_queue_families = std.AutoHashMap(u32, void).init(allocator);
    defer unique_queue_families.deinit();

    try unique_queue_families.put(indices.graphicsFamily.?, {});
    try unique_queue_families.put(indices.presentFamily.?, {});

    var queue_create_infos: std.ArrayList(vk.DeviceQueueCreateInfo) = .empty;
    defer queue_create_infos.deinit(allocator);

    var iterator = unique_queue_families.keyIterator();
    while (iterator.next()) |queue_family_ptr| {
        try queue_create_infos.append(
            allocator,
            .{
                .flags = .{},
                .queue_family_index = queue_family_ptr.*,
                .queue_count = 1,
                .p_queue_priorities = &queue_priorities,
            },
        );
    }

    var deviceFeatures: vk.PhysicalDeviceFeatures = vk.PhysicalDeviceFeatures{};
    var device_extensions: std.ArrayList([*:0]const u8) = .empty;
    defer device_extensions.deinit(allocator);
    try device_extensions.append(allocator, vk.extensions.khr_portability_subset.name);

    const deviceCreateInfo = vk.DeviceCreateInfo{
        .p_queue_create_infos = queue_create_infos.items.ptr,
        .queue_create_info_count = @intCast(queue_create_infos.items.len),
        .p_enabled_features = &deviceFeatures,
        .pp_enabled_extension_names = device_extensions.items.ptr,
        .enabled_extension_count = @intCast(device_extensions.items.len),
    };

    self.device = try self.vki.createDevice(self.physicalDevice, &deviceCreateInfo, null);
    self.vkd = DeviceWrapper.load(self.device, self.vki.dispatch.vkGetDeviceProcAddr.?);
    self.graphics_queue = self.vkd.getDeviceQueue(self.device, indices.graphicsFamily.?, 0);
    self.present_queue = self.vkd.getDeviceQueue(self.device, indices.presentFamily.?, 0);
}
