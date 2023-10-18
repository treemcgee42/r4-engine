const std = @import("std");
const builtin = @import("builtin");
const vulkan = @import("vulkan");
const glfw = @import("glfw");
const DebugMessenger = @import("./DebugMessenger.zig");
const VulkanSystem = @This();
const PipelineSystem = @import("./pipeline.zig").PipelineSystem;
const RenderPass = @import("./RenderPass.zig");
pub const RenderPassInitInfo = RenderPass.RenderPassInitInfo;
const Window = @import("../../Window.zig");
const l0 = @import("../layer0/l0.zig");
const l0vk = l0.vulkan;

allocator: std.mem.Allocator,

instance: vulkan.VkInstance,
debug_messenger: ?DebugMessenger,

physical_device: vulkan.VkPhysicalDevice,
support_details: SwapchainSupportDetails,
logical_device: vulkan.VkDevice,

graphics_queue: vulkan.VkQueue,
present_queue: vulkan.VkQueue,

command_pool: vulkan.VkCommandPool,

max_usable_sample_count: l0vk.VkSampleCountFlagBits,

pipeline_system: PipelineSystem,
renderpass_system: RenderPassSystem,
sync_system: SyncSystem,

pub const RenderPassHandle = usize;
const RenderPassSystem = struct {
    renderpasses: std.ArrayList(RenderPass),

    fn init(allocator_: std.mem.Allocator) RenderPassSystem {
        return .{
            .renderpasses = std.ArrayList(RenderPass).init(allocator_),
        };
    }

    fn deinit(self: *RenderPassSystem, system: *VulkanSystem) void {
        var i: usize = 0;
        while (i < self.renderpasses.items.len) : (i += 1) {
            self.renderpasses.items[i].deinit(system.allocator, system);
        }

        self.renderpasses.deinit();
    }

    fn create_renderpass(self: *RenderPassSystem, info: *const RenderPass.RenderPassInitInfo) !RenderPassHandle {
        const rp = try RenderPass.init(info);
        try self.renderpasses.append(rp);
        return self.renderpasses.items.len - 1;
    }

    fn get_renderpass_from_handle(self: *RenderPassSystem, handle: RenderPassHandle) *RenderPass {
        return &self.renderpasses.items[handle];
    }

    fn resize_all(self: *RenderPassSystem, system: *VulkanSystem, window: *Window) !void {
        const new_window_size = window.size();
        const new_render_area = .{
            .width = new_window_size.width,
            .height = new_window_size.height,
        };

        var i: usize = 0;
        while (i < self.renderpasses.items.len) : (i += 1) {
            try self.renderpasses.items[i].resize_callback(
                system.allocator,
                system,
                &window.swapchain.swapchain,
                new_render_area,
            );
        }
    }
};

pub const FenceHandle = usize;
pub const SemaphoreHandle = usize;
const SyncSystem = struct {
    fences: std.ArrayList(vulkan.VkFence),
    semaphores: std.ArrayList(vulkan.VkSemaphore),

    fn init(allocator_: std.mem.Allocator) SyncSystem {
        return .{
            .fences = std.ArrayList(vulkan.VkFence).init(allocator_),
            .semaphores = std.ArrayList(vulkan.VkSemaphore).init(allocator_),
        };
    }

    fn deinit(self: *SyncSystem, system: *VulkanSystem) void {
        var i: usize = 0;
        while (i < self.fences.items.len) : (i += 1) {
            vulkan.vkDestroyFence(system.logical_device, self.fences.items[i], null);
        }
        self.fences.deinit();

        i = 0;
        while (i < self.semaphores.items.len) : (i += 1) {
            vulkan.vkDestroySemaphore(system.logical_device, self.semaphores.items[i], null);
        }
        self.semaphores.deinit();
    }

    fn create_fence(self: *SyncSystem, system: *VulkanSystem) !FenceHandle {
        var fence_info = vulkan.VkFenceCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .pNext = null,
            .flags = vulkan.VK_FENCE_CREATE_SIGNALED_BIT,
        };

        var fence: vulkan.VkFence = undefined;
        var result = vulkan.vkCreateFence(
            system.logical_device,
            &fence_info,
            null,
            &fence,
        );
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }

        try self.fences.append(fence);
        return self.fences.items.len - 1;
    }

    fn create_semaphore(self: *SyncSystem, system: *VulkanSystem) !SemaphoreHandle {
        var semaphore_info = vulkan.VkSemaphoreCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
        };

        var semaphore: vulkan.VkSemaphore = undefined;
        var result = vulkan.vkCreateSemaphore(
            system.logical_device,
            &semaphore_info,
            null,
            &semaphore,
        );
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }

        try self.semaphores.append(semaphore);
        return self.semaphores.items.len - 1;
    }

    fn get_semaphore_from_handle(self: *SyncSystem, handle: SemaphoreHandle) *vulkan.VkSemaphore {
        return &self.semaphores.items[handle];
    }

    fn get_fence_from_handle(self: *SyncSystem, handle: FenceHandle) *vulkan.VkFence {
        return &self.fences.items[handle];
    }
};

pub fn create_fence(self: *VulkanSystem) !FenceHandle {
    return self.sync_system.create_fence(self);
}

pub fn create_semaphore(self: *VulkanSystem) !SemaphoreHandle {
    return self.sync_system.create_semaphore(self);
}

pub fn get_semaphore_from_handle(self: *VulkanSystem, handle: SemaphoreHandle) *vulkan.VkSemaphore {
    return self.sync_system.get_semaphore_from_handle(handle);
}

pub fn get_fence_from_handle(self: *VulkanSystem, handle: FenceHandle) *vulkan.VkFence {
    return self.sync_system.get_fence_from_handle(handle);
}

const enable_validation_layers = true;
const validation_layers = [_][*c]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const device_extensions = [_][*c]const u8{ vulkan.VK_KHR_SWAPCHAIN_EXTENSION_NAME, "VK_KHR_portability_subset" };

const max_frames_in_flight: usize = 2;

pub const VulkanError = error{
    validation_layer_not_present,
    instance_init_failed,
    no_suitable_gpu,
    surface_creation_failed,
    file_not_found,
    file_loading_failed,
    no_suitable_memory_type,
    image_load_failed,
    unsupported_layout_transition,
    no_supported_format,
    model_loading_failed,
    window_creation_failed,

    vk_error_out_of_host_memory,
    vk_error_out_of_device_memory,
    vk_error_extension_not_present,
    vk_error_layer_not_present,
    vk_error_initialization_failed,
    vk_error_feature_not_present,
    vk_error_too_many_objects,
    vk_error_device_lost,
    vk_error_surface_lost_khr,
    vk_error_native_window_in_use_khr,
    vk_error_compression_exhausted_ext,
    vk_error_invalid_opaque_capture_address_khr,
    vk_error_invalid_shader_nv,
} || std.mem.Allocator.Error;

pub fn init(allocator_: std.mem.Allocator) !VulkanSystem {
    const instance = try create_vulkan_instance(allocator_);

    var debug_messenger: ?DebugMessenger = null;
    if (enable_validation_layers) {
        debug_messenger = try DebugMessenger.init(instance);
    }

    // ---
    // We need to create a dummy window to make sure we get a device that supports
    // rendering to the surface.

    glfw.glfwWindowHint(glfw.GLFW_VISIBLE, glfw.GLFW_FALSE);
    glfw.glfwWindowHint(glfw.GLFW_CLIENT_API, glfw.GLFW_NO_API);
    var tmp_window = glfw.glfwCreateWindow(1, 1, "Temporary", null, null);
    glfw.glfwWindowHint(glfw.GLFW_VISIBLE, glfw.GLFW_TRUE);
    if (tmp_window == null) {
        return VulkanError.window_creation_failed;
    }
    defer glfw.glfwDestroyWindow(tmp_window);
    var surface = try create_surface(instance, tmp_window.?);
    defer vulkan.vkDestroySurfaceKHR(instance, surface, null);

    // ---

    const physical_device = try pick_physical_device(instance, allocator_, surface);
    const support_details = try SwapchainSupportDetails.init(allocator_, physical_device, surface);
    const logical_device = try create_logical_device(physical_device, allocator_, surface);

    // ---

    const queue_family_indices = try find_queue_families(physical_device, allocator_, surface);
    var graphics_queue: vulkan.VkQueue = undefined;
    vulkan.vkGetDeviceQueue(logical_device, queue_family_indices.graphics_family.?, 0, &graphics_queue);
    var present_queue: vulkan.VkQueue = undefined;
    vulkan.vkGetDeviceQueue(logical_device, queue_family_indices.present_family.?, 0, &present_queue);

    // ---

    const command_pool = try create_command_pool(allocator_, physical_device, logical_device, surface);

    // ---

    const max_usable_sample_count = try get_max_usable_sample_count(physical_device);

    // ---

    const pipeline_system = PipelineSystem.init(allocator_);
    const renderpass_system = RenderPassSystem.init(allocator_);
    const sync_system = SyncSystem.init(allocator_);

    // ---

    std.log.info("vulkan backend initialized", .{});

    return .{
        .allocator = allocator_,

        .instance = instance,
        .debug_messenger = debug_messenger,

        .physical_device = physical_device,
        .support_details = support_details,
        .logical_device = logical_device,

        .graphics_queue = graphics_queue,
        .present_queue = present_queue,

        .command_pool = command_pool,

        .max_usable_sample_count = max_usable_sample_count,

        .pipeline_system = pipeline_system,
        .renderpass_system = renderpass_system,
        .sync_system = sync_system,
    };
}

pub fn deinit(self: *VulkanSystem, allocator_: std.mem.Allocator) void {
    self.sync_system.deinit(self);
    self.renderpass_system.deinit(self);
    self.pipeline_system.deinit(self);

    self.support_details.deinit(allocator_);

    vulkan.vkDestroyCommandPool(self.logical_device, self.command_pool, null);

    vulkan.vkDestroyDevice(self.logical_device, null);

    if (enable_validation_layers) {
        self.debug_messenger.?.deinit();
    }

    vulkan.vkDestroyInstance(self.instance, null);
}

pub fn prep_for_deinit(self: *VulkanSystem) void {
    var result = vulkan.vkDeviceWaitIdle(self.logical_device);
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }
}

// --- Instance {{{1

fn create_vulkan_instance(allocator_: std.mem.Allocator) !l0vk.VkInstance {
    if (enable_validation_layers) {
        const found = try check_validation_layer_support(allocator_);
        if (!found) return VulkanError.validation_layer_not_present;
    }

    // --

    const app_info = l0vk.VkApplicationInfo{
        .pApplicationName = "Hello Triangle",
        .applicationVersion = .{ .major = 1, .minor = 0, .patch = 0 },

        .pEngineName = "No Engine",
        .engineVersion = .{ .major = 1, .minor = 0, .patch = 0 },
    };

    // ---

    var available_extensions = try l0vk.vkEnumerateInstanceExtensionProperties(allocator_);
    defer allocator_.free(available_extensions);

    const required_extensions = try get_required_extensions(allocator_);
    defer required_extensions.deinit();

    var create_info = l0vk.VkInstanceCreateInfo{
        .flags = .{
            .enumerate_portability_khr = true,
        },

        .pApplicationInfo = &app_info,
        .enabledExtensionNames = required_extensions.items,
        .enabledLayerNames = &.{},
    };

    if (enable_validation_layers) {
        create_info.enabledLayerNames = validation_layers[0..];
    }

    // std.log.info("{d} available extensions:", .{available_extensions_count});
    // for (available_extensions) |extension| {
    //     std.log.info("\t{s}", .{extension.extensionName});
    // }

    // ---

    const vk_instance = try l0vk.vkCreateInstance(&create_info, null);

    return vk_instance;
}

fn get_required_extensions(allocator_: std.mem.Allocator) VulkanError!std.ArrayList([*c]const u8) {
    var glfwExtensionCount: u32 = 0;
    const glfwExtensions = glfw.glfwGetRequiredInstanceExtensions(&glfwExtensionCount);

    var extensions = std.ArrayList([*c]const u8).init(allocator_);
    var i: usize = 0;
    while (i < glfwExtensionCount) : (i += 1) {
        try extensions.append(glfwExtensions[i]);
    }

    if (enable_validation_layers) {
        try extensions.append(l0vk.ExtensionNames.VK_EXT_DEBUG_UTILS);
    }

    try extensions.append(l0vk.ExtensionNames.VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2);
    try extensions.append(l0vk.ExtensionNames.VK_KHR_PORTABILITY_ENUMERATION);

    return extensions;
}

fn check_validation_layer_support(allocator_: std.mem.Allocator) !bool {
    var available_layers = try l0vk.vkEnumerateInstanceLayerProperties(allocator_);
    defer allocator_.free(available_layers);

    var i: usize = 0;
    for (validation_layers) |layer_name| {
        var layer_found = false;

        while (i < available_layers.len) : (i += 1) {
            const s1 = available_layers[i].layerName;
            const s2 = layer_name;

            // Manual strcmp.
            var j: usize = 0;
            while (j < l0vk.VK_MAX_EXTENSION_NAME_SIZE) : (j += 1) {
                // Not completely correct but...
                if (s1[j] == 0) {
                    layer_found = true;
                    break;
                }

                if (s1[j] != s2[j]) {
                    break;
                }
            }
        }

        if (!layer_found) {
            return false;
        }
    }

    return true;
}

// --- }}}1

pub fn create_surface(instance: l0vk.VkInstance, window: *glfw.GLFWwindow) VulkanError!l0vk.VkSurfaceKHR {
    var surface: vulkan.VkSurfaceKHR = null;

    const result = glfw.glfwCreateWindowSurface(@ptrCast(instance), window, null, @ptrCast(&surface));
    if (result != vulkan.VK_SUCCESS) {
        return VulkanError.surface_creation_failed;
    }

    return surface;
}

// --- Physical Device {{{1

fn pick_physical_device(
    instance: l0vk.VkInstance,
    allocator_: std.mem.Allocator,
    surface: l0vk.VkSurfaceKHR,
) !l0vk.VkPhysicalDevice {
    var devices = try l0vk.vkEnumeratePhysicalDevices(allocator_, instance);
    defer allocator_.free(devices);

    if (devices.len == 0) {
        return VulkanError.no_suitable_gpu;
    }

    var selected_device: ?l0vk.VkPhysicalDevice = null;

    // std.log.info("{d} devices found:", .{device_count});
    for (devices) |device| {
        var device_properties = l0vk.vkGetPhysicalDeviceProperties(device);
        _ = device_properties;

        var device_was_selected = false;

        if (selected_device == null) {
            const suitable = try is_device_suitable(device, allocator_, surface);
            if (suitable) {
                selected_device = device;
                device_was_selected = true;
            }
        }

        // if (device_was_selected) {
        //     std.log.info("\t{s} (selected)", .{device_properties.deviceName});
        // } else {
        //     std.log.info("\t{s}", .{device_properties.deviceName});
        // }
    }

    if (selected_device == null) {
        return VulkanError.no_suitable_gpu;
    }

    return selected_device.?;
}

fn is_device_suitable(
    device: l0vk.VkPhysicalDevice,
    allocator_: std.mem.Allocator,
    surface: l0vk.VkSurfaceKHR,
) !bool {
    const indices = try find_queue_families(device, allocator_, surface);

    const extensions_supported = try check_device_extension_support(device, allocator_);

    var swapchain_supported = false;
    if (extensions_supported) {
        var swapchain_support = try SwapchainSupportDetails.init(allocator_, device, surface);
        defer swapchain_support.deinit(allocator_);
        swapchain_supported = swapchain_support.formats.len > 0 and swapchain_support.present_modes.len > 0;
    }

    const supported_features = l0vk.vkGetPhysicalDeviceFeatures(device);

    return indices.is_complete() and extensions_supported and swapchain_supported and supported_features.samplerAnisotropy;
}

const QueueFamilyIndices = struct {
    graphics_family: ?u32,
    present_family: ?u32,

    fn init_null() QueueFamilyIndices {
        return .{
            .graphics_family = null,
            .present_family = null,
        };
    }

    fn is_complete(self: *const QueueFamilyIndices) bool {
        return (self.graphics_family != null and self.present_family != null);
    }
};

pub fn find_queue_families(
    physical_device: l0vk.VkPhysicalDevice,
    allocator_: std.mem.Allocator,
    surface: l0vk.VkSurfaceKHR,
) !QueueFamilyIndices {
    var indices = QueueFamilyIndices.init_null();

    var queue_families = try l0vk.vkGetPhysicalDeviceQueueFamilyProperties(allocator_, physical_device);
    defer allocator_.free(queue_families);

    var i: u32 = 0;
    while (i < queue_families.len) : (i += 1) {
        if (indices.is_complete()) break;

        const queue_family = queue_families[i];

        if (queue_family.queueFlags.graphics) {
            indices.graphics_family = i;
        }

        const present_support = try l0vk.vkGetPhysicalDeviceSurfaceSupportKHR(
            physical_device,
            i,
            surface,
        );
        if (present_support) {
            indices.present_family = i;
        }
    }

    return indices;
}

fn check_device_extension_support(device: l0vk.VkPhysicalDevice, allocator_: std.mem.Allocator) !bool {
    const available_extensions = try l0vk.vkEnumerateDeviceExtensionProperties(allocator_, device, null);
    defer allocator_.free(available_extensions);

    var found_exensions: usize = 0;
    for (device_extensions) |extension| {
        var found = false;
        for (available_extensions) |available_extension| {
            // Manual strcmp.
            var i: usize = 0;
            while (true) : (i += 1) {
                if (available_extension.extensionName[i] == 0 or i >= l0vk.VK_MAX_EXTENSION_NAME_SIZE) {
                    found = true;
                }

                if (available_extension.extensionName[i] != extension[i]) {
                    break;
                }
            }
        }

        if (found) {
            found_exensions += 1;
        }
    }

    return found_exensions == device_extensions.len;
}

fn get_max_usable_sample_count(physical_device: l0vk.VkPhysicalDevice) VulkanError!l0vk.VkSampleCountFlagBits {
    const physical_device_properties = l0vk.vkGetPhysicalDeviceProperties(physical_device);
    const counts: l0vk.VkSampleCountFlags = @bitCast(@as(u32, @bitCast(physical_device_properties.limits.framebufferColorSampleCounts)) & @as(u32, @bitCast(physical_device_properties.limits.framebufferDepthSampleCounts)));

    if (counts.bit_64) {
        return .VK_SAMPLE_COUNT_64_BIT;
    }
    if (counts.bit_32) {
        return .VK_SAMPLE_COUNT_32_BIT;
    }
    if (counts.bit_16) {
        return .VK_SAMPLE_COUNT_16_BIT;
    }
    if (counts.bit_8) {
        return .VK_SAMPLE_COUNT_8_BIT;
    }
    if (counts.bit_4) {
        return .VK_SAMPLE_COUNT_4_BIT;
    }
    if (counts.bit_2) {
        return .VK_SAMPLE_COUNT_2_BIT;
    }

    return .VK_SAMPLE_COUNT_1_BIT;
}

// --- }}}1

// --- Logical Device {{{1

fn create_logical_device(
    physical_device: l0vk.VkPhysicalDevice,
    allocator_: std.mem.Allocator,
    surface: l0vk.VkSurfaceKHR,
) !vulkan.VkDevice {
    const queue_family_indices = try find_queue_families(
        physical_device,
        allocator_,
        surface,
    );

    var unique_queue_families = std.ArrayList(u32).init(allocator_);
    defer unique_queue_families.deinit();
    const indices = [_]u32{ queue_family_indices.graphics_family.?, queue_family_indices.present_family.? };
    for (indices) |index| {
        var should_insert = true;

        var i: usize = 0;
        while (i < unique_queue_families.items.len) : (i += 1) {
            if (unique_queue_families.items[i] == index) {
                should_insert = false;
            }
        }

        if (should_insert) {
            try unique_queue_families.append(index);
        }
    }

    var queue_create_infos = std.ArrayList(l0vk.VkDeviceQueueCreateInfo).init(allocator_);
    defer queue_create_infos.deinit();
    const queue_priority: f32 = 1.0;
    for (unique_queue_families.items) |queue_family| {
        var queue_create_info: l0vk.VkDeviceQueueCreateInfo = .{
            .queueFamilyIndex = queue_family,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        };

        try queue_create_infos.append(queue_create_info);
    }

    const device_features: l0vk.VkPhysicalDeviceFeatures = .{
        .samplerAnisotropy = true,
    };

    var create_info = l0vk.VkDeviceCreateInfo{
        .queueCreateInfos = queue_create_infos.items,
        .pEnabledFeatures = &device_features,
        .enabledExtensionNames = &device_extensions,
    };
    if (enable_validation_layers) {
        create_info.enabledLayerNames = &validation_layers;
    }

    const logical_device = try l0vk.vkCreateDevice(
        physical_device,
        &create_info,
        null,
    );
    return logical_device;
}

// --- }}}1

// --- Swapchain support {{{1

pub const SwapchainSupportDetails = struct {
    capabilities: l0vk.VkSurfaceCapabilitiesKHR,
    formats: []l0vk.VkSurfaceFormatKHR,
    present_modes: []l0vk.VkPresentModeKHR,

    pub fn init(
        allocator_: std.mem.Allocator,
        physical_device: l0vk.VkPhysicalDevice,
        surface: l0vk.VkSurfaceKHR,
    ) !SwapchainSupportDetails {
        const capabilities = try l0vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface);

        const formats = try l0vk.vkGetPhysicalDeviceSurfaceFormatsKHR(
            allocator_,
            physical_device,
            surface,
        );

        const present_modes = try l0vk.vkGetPhysicalDeviceSurfacePresentModesKHR(
            allocator_,
            physical_device,
            surface,
        );

        return .{
            .capabilities = capabilities,
            .formats = formats,
            .present_modes = present_modes,
        };
    }

    pub fn deinit(self: *SwapchainSupportDetails, allocator_: std.mem.Allocator) void {
        allocator_.free(self.formats);
        allocator_.free(self.present_modes);
    }
};

pub const SwapchainSettings = struct {
    surface_format: l0vk.VkSurfaceFormatKHR,
    present_mode: l0vk.VkPresentModeKHR,
    extent: l0vk.VkExtent2D,
    min_image_count: u32,
    // Right now, we only support up to two distinct queue families,
    // which should only be the case if the graphics and present
    // queues are distinct.
    image_sharing_mode: vulkan.VkSharingMode,
    queue_family_index_count: u32,
    queue_family_indices: [2]u32,

    capabilities: l0vk.VkSurfaceCapabilitiesKHR,

    logical_device: l0vk.VkDevice,
    surface: l0vk.VkSurfaceKHR,
};

/// We abstract this because the renderpass might like to know some of this information.
/// By passing the same info to both the renderpass and swapchain, we can ensure the
/// objects are created with the same attributes, for example.
pub fn query_swapchain_settings(
    allocator_: std.mem.Allocator,
    physical_device: vulkan.VkPhysicalDevice,
    logical_device: vulkan.VkDevice,
    surface: vulkan.VkSurfaceKHR,
) !SwapchainSettings {
    var swap_chain_support = try SwapchainSupportDetails.init(allocator_, physical_device, surface);
    defer swap_chain_support.deinit(allocator_);

    const surface_format = choose_swap_surface_format(swap_chain_support.formats);
    const present_mode = choose_swap_chain_present_mode(swap_chain_support.present_modes);
    const extent = choose_swap_extent(swap_chain_support.capabilities);

    var image_count: u32 = swap_chain_support.capabilities.minImageCount + 1;
    if (swap_chain_support.capabilities.maxImageCount > 0 and
        image_count > swap_chain_support.capabilities.maxImageCount)
    {
        image_count = swap_chain_support.capabilities.maxImageCount;
    }

    var image_sharing_mode: vulkan.VkSharingMode = undefined;
    var queue_family_index_count: u32 = undefined;
    const indices = try find_queue_families(physical_device, allocator_, surface);
    const queue_family_indices = [_]u32{ indices.graphics_family.?, indices.present_family.? };
    if (indices.graphics_family != indices.present_family) {
        image_sharing_mode = vulkan.VK_SHARING_MODE_CONCURRENT;
        // i.e. the graphics and present queues are distinct.
        queue_family_index_count = 2;
    } else {
        image_sharing_mode = vulkan.VK_SHARING_MODE_EXCLUSIVE;
        queue_family_index_count = 0;
    }

    return SwapchainSettings{
        .surface_format = surface_format,
        .present_mode = present_mode,
        .extent = extent,
        .min_image_count = image_count,

        .image_sharing_mode = image_sharing_mode,
        .queue_family_index_count = queue_family_index_count,
        .queue_family_indices = queue_family_indices,

        .capabilities = swap_chain_support.capabilities,

        .logical_device = logical_device,
        .surface = surface,
    };
}

fn choose_swap_surface_format(available_formats: []const l0vk.VkSurfaceFormatKHR) l0vk.VkSurfaceFormatKHR {
    for (available_formats) |available_format| {
        if (available_format.format == .b8g8r8a8_srgb and available_format.colorSpace == .srgb_nonlinear_khr) {
            return available_format;
        }
    }

    return available_formats[0];
}

fn choose_swap_chain_present_mode(available_present_modes: []const l0vk.VkPresentModeKHR) l0vk.VkPresentModeKHR {
    for (available_present_modes) |available_present_mode| {
        if (available_present_mode == .mailbox_khr) {
            return available_present_mode;
        }
    }

    return .fifo_khr;
}

fn choose_swap_extent(capabilities: l0vk.VkSurfaceCapabilitiesKHR) l0vk.VkExtent2D {
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    } else {
        const width = @as(u32, @intCast(glfw.glfwGetVideoMode(glfw.glfwGetPrimaryMonitor()).*.width));
        const height = @as(u32, @intCast(glfw.glfwGetVideoMode(glfw.glfwGetPrimaryMonitor()).*.height));

        var actual_extent = l0vk.VkExtent2D{
            .width = width,
            .height = height,
        };

        actual_extent.width = std.math.clamp(
            actual_extent.width,
            capabilities.minImageExtent.width,
            capabilities.maxImageExtent.width,
        );
        actual_extent.height = std.math.clamp(
            actual_extent.height,
            capabilities.minImageExtent.height,
            capabilities.maxImageExtent.height,
        );

        return actual_extent;
    }
}

// --- }}}1

// --- Command. {{{1

fn create_command_pool(
    allocator_: std.mem.Allocator,
    physical_device: vulkan.VkPhysicalDevice,
    logical_device: vulkan.VkDevice,
    surface: vulkan.VkSurfaceKHR,
) !vulkan.VkCommandPool {
    const queue_family_indices = try find_queue_families(physical_device, allocator_, surface);

    const pool_info = vulkan.VkCommandPoolCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .queueFamilyIndex = queue_family_indices.graphics_family.?,
        .flags = vulkan.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .pNext = null,
    };

    var command_pool: vulkan.VkCommandPool = undefined;
    const result = vulkan.vkCreateCommandPool(logical_device, &pool_info, null, &command_pool);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            else => unreachable,
        }
    }

    return command_pool;
}

// --- }}}1

pub fn create_renderpass(self: *VulkanSystem, info: *const RenderPass.RenderPassInitInfo) !RenderPassHandle {
    return self.renderpass_system.create_renderpass(info);
}

pub fn get_renderpass_from_handle(self: *VulkanSystem, handle: RenderPassHandle) *RenderPass {
    return self.renderpass_system.get_renderpass_from_handle(handle);
}

pub fn handle_swapchain_resize_for_renderpasses(self: *VulkanSystem, window: *Window) !void {
    return self.renderpass_system.resize_all(self, window);
}

// ---

pub fn begin_command_buffer(self: *VulkanSystem, command_buffer: vulkan.VkCommandBuffer) !void {
    _ = self;
    const begin_info = vulkan.VkCommandBufferBeginInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = 0,
        .pInheritanceInfo = null,
        .pNext = null,
    };

    var result = vulkan.vkBeginCommandBuffer(command_buffer, &begin_info);
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }
}

pub fn end_command_buffer(self: *VulkanSystem, command_buffer: vulkan.VkCommandBuffer) !void {
    _ = self;
    var result = vulkan.vkEndCommandBuffer(command_buffer);
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }
}

pub fn submit_command_buffer(
    self: *VulkanSystem,
    p_command_buffer: *vulkan.VkCommandBuffer,
    wait_semaphore: SemaphoreHandle,
    signal_semaphore: SemaphoreHandle,
    fence: ?FenceHandle,
) !void {
    const wait_semaphores = [_]vulkan.VkSemaphore{
        self.sync_system.get_semaphore_from_handle(wait_semaphore).*,
    };
    const wait_stages = [_]vulkan.VkPipelineStageFlags{
        vulkan.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
    };
    const signal_semaphores = [_]vulkan.VkSemaphore{
        self.sync_system.get_semaphore_from_handle(signal_semaphore).*,
    };

    const submit_info = vulkan.VkSubmitInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = wait_semaphores.len,
        .pWaitSemaphores = wait_semaphores[0..].ptr,
        .pWaitDstStageMask = wait_stages[0..].ptr,
        .commandBufferCount = 1,
        .pCommandBuffers = p_command_buffer,
        .signalSemaphoreCount = signal_semaphores.len,
        .pSignalSemaphores = signal_semaphores[0..].ptr,

        .pNext = null,
    };

    var submit_fence: vulkan.VkFence = null;
    if (fence != null) {
        submit_fence = self.sync_system.get_fence_from_handle(fence.?).*;
    }
    var result = vulkan.vkQueueSubmit(
        self.graphics_queue,
        1,
        &submit_info,
        submit_fence,
    );
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }
}
