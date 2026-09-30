const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("zglfw");
const builtin = @import("builtin");

const Self = @This();

const QueueFamilyIndices = struct {
    graphics_family: ?u32,
    present_family: ?u32,

    pub fn isComplete(self: @This()) bool {
        return self.graphics_family != null and self.present_family != null;
    }
};

const SwapChainSupportDetails = struct {
    capabilities: vk.SurfaceCapabilitiesKHR,
    formats: []vk.SurfaceFormatKHR,
    present_modes: []vk.PresentModeKHR,
};

const BaseWrapper = vk.BaseWrapper;
const InstanceWrapper = vk.InstanceWrapper;
const DeviceWrapper = vk.DeviceWrapper;
const enable_vaildation = builtin.mode == .Debug;
const validation_layer = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};
const device_extensions = [_][*:0]const u8{ vk.extensions.khr_portability_subset.name, vk.extensions.khr_swapchain.name };

vkb: BaseWrapper = undefined,
vki: InstanceWrapper = undefined,
vkd: DeviceWrapper = undefined,
instance: vk.Instance = undefined,
surface: vk.SurfaceKHR = undefined,
initialized: bool = false,
device: vk.Device = undefined,
physical_device: vk.PhysicalDevice = undefined,
graphics_queue: vk.Queue = undefined,
present_queue: vk.Queue = undefined,
swap_chain: vk.SwapchainKHR = undefined,
swap_chain_images: []vk.Image = &.{},
swap_chain_image_format: vk.Format = undefined,
swap_chain_extent: vk.Extent2D = undefined,
swap_chain_image_view: []vk.ImageView = &.{},

pub fn init(self: *Self, extensions: [][*:0]const u8, allocator: std.mem.Allocator) !void {
    self.vkb = BaseWrapper.load(glfw.getInstanceProcAddress);

    if (enable_vaildation) {
        if (!try self.checkValidationSupport(allocator)) {
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

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    defer allocator.free(self.swap_chain_images);
    defer allocator.free(self.swap_chain_image_view);
    for (self.swap_chain_image_view) |view| {
        self.vkd.destroyImageView(self.device, view, null);
    }
    self.vkd.destroySwapchainKHR(self.device, self.swap_chain, null);
    self.vkd.destroyDevice(self.device, null);
    self.vki.destroySurfaceKHR(self.instance, self.surface, null);
    if (!self.initialized) return;
    self.vki.destroyInstance(self.instance, null);
    self.initialized = false;
}

pub fn createSurface(self: *Self, window: *glfw.Window) !void {
    try glfw.createWindowSurface(self.instance, window, null, &self.surface);
}

pub fn checkValidationSupport(self: *Self, allocator: std.mem.Allocator) !bool {
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

pub fn pickPhysicalDevice(self: *Self, allocator: std.mem.Allocator) !void {
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
    self.physical_device = pDevice;
    std.debug.print("selected GPU : {}\n", .{pDevice});
}

pub fn isDeviceSuitable(self: *Self, physical_device: vk.PhysicalDevice, allocator: std.mem.Allocator) bool {
    const indicies = self.findQueueFamilyIndices(physical_device, allocator) catch |err| {
        std.debug.print("Encountred {} while trying to get queue indices for {}, rejecting physical device as unsuitable", .{ err, physical_device });
        return false;
    };
    const extension_check = self.checkDeviceExtensionSupport(physical_device, allocator) catch |e| {
        std.debug.print("Failed to check extenstion support for physical device :{}", .{e});
        return false;
    };
    var swap_chain_check: bool = false;
    if (extension_check) {
        const swap_chain_support = self.querySwapChainSupport(physical_device, allocator) catch |e| {
            std.debug.print("Failed to check swap chain support for physical device :{}", .{e});
            return false;
        };
        swap_chain_check = swap_chain_support.formats.len != 0 and swap_chain_support.present_modes.len != 0;
        defer allocator.free(swap_chain_support.formats);
        defer allocator.free(swap_chain_support.present_modes);
    }
    return indicies.isComplete() and extension_check and swap_chain_check;
}

pub fn checkDeviceExtensionSupport(self: *Self, physical_device: vk.PhysicalDevice, allocator: std.mem.Allocator) !bool {
    var extension_count: u32 = undefined;
    _ = self.vki.enumerateDeviceExtensionProperties(physical_device, null, &extension_count, null) catch |e| {
        std.debug.print("Failed to get exentesion count for physical device :{}", .{e});
        return false;
    };
    const available_extensions = try allocator.alloc(vk.ExtensionProperties, extension_count);
    defer allocator.free(available_extensions);

    _ = self.vki.enumerateDeviceExtensionProperties(physical_device, null, &extension_count, available_extensions.ptr) catch |e| {
        std.debug.print("Failed to get exentesion properties for physical device :{}", .{e});
        return false;
    };

    for (device_extensions) |req| {
        var found = false;

        for (available_extensions) |ext| {
            const ext_name: [*:0]const u8 = @ptrCast(&ext.extension_name);
            if (std.mem.eql(u8, std.mem.span(req), std.mem.span(ext_name))) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

pub fn findQueueFamilyIndices(self: *Self, physical_device: vk.PhysicalDevice, allocator: std.mem.Allocator) !QueueFamilyIndices {
    var queueCount: u32 = undefined;
    _ = self.vki.getPhysicalDeviceQueueFamilyProperties(physical_device, &queueCount, null);

    const available_queues = try allocator.alloc(vk.QueueFamilyProperties, queueCount);
    defer allocator.free(available_queues);

    _ = self.vki.getPhysicalDeviceQueueFamilyProperties(physical_device, &queueCount, available_queues.ptr);

    const graphicsFamily = getGraphicsQueueIndex(available_queues, queueCount);
    const presentFamily: ?u32 = getPrensetQueueIndex(self, physical_device, available_queues, queueCount);
    return QueueFamilyIndices{ .graphics_family = graphicsFamily, .present_family = presentFamily };
}

fn getGraphicsQueueIndex(available_queues: []vk.QueueFamilyProperties, queueCount: u32) ?u32 {
    for (available_queues[0..queueCount], 0..) |*queue, ind| {
        const index: u32 = @intCast(ind);
        if (queue.queue_flags.graphics_bit) return index;
    }
    return null;
}

fn getPrensetQueueIndex(self: *Self, physical_device: vk.PhysicalDevice, available_queues: []vk.QueueFamilyProperties, queueCount: u32) ?u32 {
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

fn querySwapChainSupport(self: *Self, physical_device: vk.PhysicalDevice, allocator: std.mem.Allocator) !SwapChainSupportDetails {
    const capabilities = try self.vki.getPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, self.surface);

    var format_count: u32 = undefined;
    _ = try self.vki.getPhysicalDeviceSurfaceFormatsKHR(
        physical_device,
        self.surface,
        &format_count,
        null,
    );
    var formats: []vk.SurfaceFormatKHR = &.{};
    if (format_count > 0) {
        formats = try allocator.alloc(vk.SurfaceFormatKHR, format_count);
        _ = try self.vki.getPhysicalDeviceSurfaceFormatsKHR(physical_device, self.surface, &format_count, formats.ptr);
    }

    var present_mode_count: u32 = undefined;
    _ = try self.vki.getPhysicalDeviceSurfacePresentModesKHR(
        physical_device,
        self.surface,
        &present_mode_count,
        null,
    );
    var present_modes: []vk.PresentModeKHR = &.{};
    if (present_mode_count > 0) {
        present_modes = try allocator.alloc(vk.PresentModeKHR, present_mode_count);
        _ = try self.vki.getPhysicalDeviceSurfacePresentModesKHR(physical_device, self.surface, &present_mode_count, present_modes.ptr);
    }
    return SwapChainSupportDetails{
        .capabilities = capabilities,
        .formats = formats,
        .present_modes = present_modes,
    };
}

fn chooseSwapSurfaceFormat(available_foramts: []vk.SurfaceFormatKHR) vk.SurfaceFormatKHR {
    for (available_foramts) |format| {
        if (format.color_space == vk.ColorSpaceKHR.colorspace_srgb_nonlinear_khr and format.format == vk.Format.a8b8g8r8_srgb_pack32) {
            return format;
        }
    }
    return available_foramts[0];
}

fn chooseSwapPresentMode(available_modes: []vk.PresentModeKHR) vk.PresentModeKHR {
    for (available_modes) |mode| {
        if (mode == vk.PresentModeKHR.mailbox_khr) {
            return mode;
        }
    }
    return vk.PresentModeKHR.fifo_khr;
}

fn chooseSwapExtent(window: *glfw.Window, capabilities: vk.SurfaceCapabilitiesKHR) vk.Extent2D {
    if (capabilities.current_extent.width != std.math.maxInt(u32)) {
        return capabilities.current_extent;
    } else {
        const size = window.getFramebufferSize();

        var actual_extent = vk.Extent2D{
            .width = @intCast(size[0]),
            .height = @intCast(size[1]),
        };

        actual_extent.width = std.math.clamp(actual_extent.width, capabilities.min_image_extent.width, capabilities.max_image_extent.width);
        actual_extent.height = std.math.clamp(actual_extent.height, capabilities.min_image_extent.height, capabilities.max_image_extent.height);

        return actual_extent;
    }
}

pub fn createSwapChain(self: *Self, window: *glfw.Window, allocator: std.mem.Allocator) !void {
    const swap_chain_support = try self.querySwapChainSupport(self.physical_device, allocator);
    defer allocator.free(swap_chain_support.formats);
    defer allocator.free(swap_chain_support.present_modes);

    const surface_format = chooseSwapSurfaceFormat(swap_chain_support.formats);
    const present_mode = chooseSwapPresentMode(swap_chain_support.present_modes);
    const extent = chooseSwapExtent(window, swap_chain_support.capabilities);

    var image_count: u32 = swap_chain_support.capabilities.min_image_count + 1;

    if (swap_chain_support.capabilities.max_image_count > 0 and image_count > swap_chain_support.capabilities.max_image_count) {
        image_count = swap_chain_support.capabilities.max_image_count;
    }

    const indices = try self.findQueueFamilyIndices(self.physical_device, allocator);
    const queue_family_indices = [_]u32{ indices.graphics_family.?, indices.present_family.? };

    var create_info = vk.SwapchainCreateInfoKHR{
        .surface = self.surface,
        .image_format = surface_format.format,
        .image_color_space = surface_format.color_space,
        .image_extent = extent,
        .present_mode = present_mode,
        .min_image_count = image_count,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true },
        .pre_transform = swap_chain_support.capabilities.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .clipped = vk.Bool32.true,
        .old_swapchain = .null_handle,
        .image_sharing_mode = if (indices.graphics_family.? != indices.present_family.?) .concurrent else .exclusive,
        .queue_family_index_count = if (indices.graphics_family.? != indices.present_family.?) 2 else 0,
        .p_queue_family_indices = if (indices.graphics_family.? != indices.present_family.?) &queue_family_indices else null,
    };

    self.swap_chain = try self.vkd.createSwapchainKHR(self.device, &create_info, null);
    _ = try self.vkd.getSwapchainImagesKHR(self.device, self.swap_chain, &image_count, null);
    self.swap_chain_images = try allocator.alloc(vk.Image, image_count);
    _ = try self.vkd.getSwapchainImagesKHR(self.device, self.swap_chain, &image_count, self.swap_chain_images.ptr);

    self.swap_chain_image_format = surface_format.format;
    self.swap_chain_extent = extent;
}

pub fn createImageViews(self: *Self, allocator: std.mem.Allocator) !void {
    self.swap_chain_image_view = try allocator.alloc(vk.ImageView, self.swap_chain_images.len);
    for (self.swap_chain_images, 0..) |image, ind| {
        var create_info = vk.ImageViewCreateInfo{
            .image = image,
            .view_type = .@"2d",
            .format = self.swap_chain_image_format,
            .components = vk.ComponentMapping{
                .a = .identity,
                .r = .identity,
                .g = .identity,
                .b = .identity,
            },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_array_layer = 0,
                .base_mip_level = 0,
                .layer_count = 1,
                .level_count = 1,
            },
        };

        self.swap_chain_image_view[ind] = try self.vkd.createImageView(self.device, &create_info, null);
    }
}

// Logical device creation.
pub fn createLogicalDevice(self: *Self, allocator: std.mem.Allocator) !void {
    const indices = try self.findQueueFamilyIndices(self.physical_device, allocator);
    const queue_priorities = [_]f32{1.0};

    var unique_queue_families = std.AutoHashMap(u32, void).init(allocator);
    defer unique_queue_families.deinit();

    try unique_queue_families.put(indices.graphics_family.?, {});
    try unique_queue_families.put(indices.present_family.?, {});

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

    const deviceCreateInfo = vk.DeviceCreateInfo{
        .p_queue_create_infos = queue_create_infos.items.ptr,
        .queue_create_info_count = @intCast(queue_create_infos.items.len),
        .p_enabled_features = &deviceFeatures,
        .pp_enabled_extension_names = &device_extensions,
        .enabled_extension_count = @intCast(device_extensions.len),
    };

    self.device = try self.vki.createDevice(self.physical_device, &deviceCreateInfo, null);
    self.vkd = DeviceWrapper.load(self.device, self.vki.dispatch.vkGetDeviceProcAddr.?);
    self.graphics_queue = self.vkd.getDeviceQueue(self.device, indices.graphics_family.?, 0);
    self.present_queue = self.vkd.getDeviceQueue(self.device, indices.present_family.?, 0);
}
