const c_string = @cImport({
    @cInclude("string.h");
});

const std = @import("std");
const builtin = @import("builtin");

const vulkan = @import("../c.zig").vulkan;
const glfw = @import("../c.zig").glfw;

const DebugMessenger = @import("./debug.zig");
const Swapchain = @import("./swapchain.zig");
const GraphicsPipeline = @import("./graphics_pipeline.zig");
const Vertex = @import("../vertex.zig");

const VulkanSystem = @This();

allocator: std.mem.Allocator,

instance: vulkan.VkInstance,
debug_messenger: ?DebugMessenger,

surface: vulkan.VkSurfaceKHR,

physical_device: vulkan.VkPhysicalDevice,
logical_device: vulkan.VkDevice,

graphics_queue: vulkan.VkQueue,
present_queue: vulkan.VkQueue,

swapchain: Swapchain,
render_pass: vulkan.VkRenderPass,
graphics_pipeline: GraphicsPipeline,

vertex_buffer: VertexBuffer,

command_pool: vulkan.VkCommandPool,
command_buffers: []vulkan.VkCommandBuffer,

image_available_semaphores: []vulkan.VkSemaphore,
render_finished_semaphores: []vulkan.VkSemaphore,
in_flight_fences: []vulkan.VkFence,

current_frame: usize = 0,

framebuffer_resized: bool = false,

pub const VulkanError = error{
    validation_layer_not_present,
    instance_init_failed,
    no_suitable_gpu,
    surface_creation_failed,
    file_not_found,
    file_loading_failed,
    no_suitable_memory_type,

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

const enable_validation_layers = (builtin.mode == .Debug);
const validation_layers = [_][*c]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const device_extensions = [_][*c]const u8{ vulkan.VK_KHR_SWAPCHAIN_EXTENSION_NAME, "VK_KHR_portability_subset" };

const max_frames_in_flight: usize = 2;

pub fn init(allocator_: std.mem.Allocator, window: *glfw.GLFWwindow) VulkanError!VulkanSystem {
    const instance = try create_vulkan_instance(allocator_);
    var debug_messenger: ?DebugMessenger = null;
    if (enable_validation_layers) {
        debug_messenger = try DebugMessenger.init(instance);
    }

    const surface = try create_surface(instance, window);

    const physical_device = try pick_physical_device(instance, allocator_, surface);
    const logical_device = try create_logical_device(physical_device, allocator_, surface);

    const queue_family_indices = try find_queue_families(physical_device, allocator_, surface);
    var graphics_queue: vulkan.VkQueue = undefined;
    vulkan.vkGetDeviceQueue(logical_device, queue_family_indices.graphics_family.?, 0, &graphics_queue);
    var present_queue: vulkan.VkQueue = undefined;
    vulkan.vkGetDeviceQueue(logical_device, queue_family_indices.present_family.?, 0, &present_queue);

    const swapchain_settings = try Swapchain.query_swapchain_settings(allocator_, physical_device, logical_device, surface);
    const render_pass = try create_render_pass(logical_device, swapchain_settings.surface_format.format);
    const swapchain = try Swapchain.init(allocator_, window, physical_device, logical_device, surface, render_pass);

    const graphics_pipeline = try GraphicsPipeline.init(allocator_, logical_device, &swapchain, render_pass);

    const vertex_buffer = try VertexBuffer.init(physical_device, logical_device);

    const command_pool = try create_command_pool(allocator_, physical_device, logical_device, surface);
    const command_buffers = try create_command_buffers(allocator_, logical_device, command_pool);

    const sync_objects = try create_sync_objects(allocator_, logical_device);

    return VulkanSystem{
        .allocator = allocator_,

        .instance = instance,
        .debug_messenger = debug_messenger,

        .surface = surface,

        .physical_device = physical_device,
        .logical_device = logical_device,

        .graphics_queue = graphics_queue,
        .present_queue = present_queue,

        .swapchain = swapchain,
        .render_pass = render_pass,
        .graphics_pipeline = graphics_pipeline,

        .vertex_buffer = vertex_buffer,

        .command_pool = command_pool,
        .command_buffers = command_buffers,

        .image_available_semaphores = sync_objects.image_available_semaphores,
        .render_finished_semaphores = sync_objects.render_finished_semaphores,
        .in_flight_fences = sync_objects.in_flight_fences,
    };
}

pub fn deinit(self: *VulkanSystem) void {
    var result = vulkan.vkDeviceWaitIdle(self.logical_device);
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }

    var i: usize = 0;
    while (i < max_frames_in_flight) : (i += 1) {
        vulkan.vkDestroySemaphore(self.logical_device, self.image_available_semaphores[i], null);
        vulkan.vkDestroySemaphore(self.logical_device, self.render_finished_semaphores[i], null);
        vulkan.vkDestroyFence(self.logical_device, self.in_flight_fences[i], null);
    }
    self.allocator.free(self.image_available_semaphores);
    self.allocator.free(self.render_finished_semaphores);
    self.allocator.free(self.in_flight_fences);

    vulkan.vkDestroyCommandPool(self.logical_device, self.command_pool, null);

    self.allocator.free(self.command_buffers);

    self.graphics_pipeline.deinit();
    vulkan.vkDestroyRenderPass(self.logical_device, self.render_pass, null);
    self.swapchain.deinit();

    self.vertex_buffer.deinit(self.logical_device);

    vulkan.vkDestroyDevice(self.logical_device, null);

    if (enable_validation_layers) {
        self.debug_messenger.?.deinit();
    }

    vulkan.vkDestroySurfaceKHR(self.instance, self.surface, null);
    vulkan.vkDestroyInstance(self.instance, null);
}

pub fn draw_frame(self: *VulkanSystem) VulkanError!void {
    // --- Wait for the previous frame to finish.

    var result = vulkan.vkWaitForFences(self.logical_device, 1, &self.in_flight_fences[self.current_frame], vulkan.VK_TRUE, std.math.maxInt(u64));
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }

    // --- Acquire the next image.

    var image_index: u32 = undefined;
    result = vulkan.vkAcquireNextImageKHR(
        self.logical_device,
        self.swapchain.swapchain,
        std.math.maxInt(u64),
        self.image_available_semaphores[self.current_frame],
        @ptrCast(vulkan.VK_NULL_HANDLE),
        &image_index,
    );
    if (result != vulkan.VK_SUCCESS and result != vulkan.VK_SUBOPTIMAL_KHR) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_DATE_KHR => {
                const swapchain_settings = try Swapchain.query_swapchain_settings(
                    self.allocator,
                    self.physical_device,
                    self.logical_device,
                    self.surface,
                );
                try self.swapchain.recreate_swapchain(swapchain_settings);
                return;
            },
            else => unreachable,
        }
    }

    // --- Reset the fence if submitting work.

    result = vulkan.vkResetFences(self.logical_device, 1, &self.in_flight_fences[self.current_frame]);
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }

    // --- Record command buffer.

    result = vulkan.vkResetCommandBuffer(self.command_buffers[self.current_frame], 0);
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }

    try self.record_command_buffer(self.command_buffers[self.current_frame], image_index);

    // --- Submit command buffer.

    const wait_semaphores = [_]vulkan.VkSemaphore{self.image_available_semaphores[self.current_frame]};
    const wait_stages = [_]vulkan.VkPipelineStageFlags{vulkan.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
    const signal_semaphores = [_]vulkan.VkSemaphore{self.render_finished_semaphores[self.current_frame]};

    const submit_info = vulkan.VkSubmitInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = wait_semaphores.len,
        .pWaitSemaphores = wait_semaphores[0..].ptr,
        .pWaitDstStageMask = wait_stages[0..].ptr,
        .commandBufferCount = 1,
        .pCommandBuffers = &self.command_buffers[self.current_frame],
        .signalSemaphoreCount = signal_semaphores.len,
        .pSignalSemaphores = signal_semaphores[0..].ptr,

        .pNext = null,
    };

    result = vulkan.vkQueueSubmit(self.graphics_queue, 1, &submit_info, self.in_flight_fences[self.current_frame]);
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }

    // --- Present.

    const swapchains = [_]vulkan.VkSwapchainKHR{self.swapchain.swapchain};
    const present_info = vulkan.VkPresentInfoKHR{
        .sType = vulkan.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = signal_semaphores[0..].ptr,
        .swapchainCount = swapchains.len,
        .pSwapchains = swapchains[0..].ptr,
        .pImageIndices = &image_index,

        .pResults = null,
        .pNext = null,
    };

    result = vulkan.vkQueuePresentKHR(self.present_queue, &present_info);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_DATE_KHR => {
                const swapchain_settings = try Swapchain.query_swapchain_settings(
                    self.allocator,
                    self.physical_device,
                    self.logical_device,
                    self.surface,
                );
                try self.swapchain.recreate_swapchain(swapchain_settings);
            },
            vulkan.VK_SUBOPTIMAL_KHR => {
                const swapchain_settings = try Swapchain.query_swapchain_settings(
                    self.allocator,
                    self.physical_device,
                    self.logical_device,
                    self.surface,
                );
                try self.swapchain.recreate_swapchain(swapchain_settings);
            },
            else => unreachable,
        }
    }

    if (self.framebuffer_resized) {
        self.framebuffer_resized = false;
        const swapchain_settings = try Swapchain.query_swapchain_settings(
            self.allocator,
            self.physical_device,
            self.logical_device,
            self.surface,
        );
        try self.swapchain.recreate_swapchain(swapchain_settings);
    }

    self.current_frame = (self.current_frame + 1) % max_frames_in_flight;
}

fn create_vulkan_instance(allocator_: std.mem.Allocator) VulkanError!vulkan.VkInstance {
    var result: vulkan.VkResult = undefined;

    if (enable_validation_layers) {
        const found = try check_validation_layer_support(allocator_);
        if (!found) return VulkanError.validation_layer_not_present;
    }

    // --

    const app_info = vulkan.VkApplicationInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "Hello Triangle",
        .applicationVersion = vulkan.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "No Engine",
        .engineVersion = vulkan.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = vulkan.VK_API_VERSION_1_0,
        .pNext = null,
    };

    // ---

    var createInfo = vulkan.VkInstanceCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .pNext = null,
        .flags = 0,
        .enabledExtensionCount = 0,
        .ppEnabledExtensionNames = null,
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
    };

    if (enable_validation_layers) {
        createInfo.enabledLayerCount = validation_layers.len;
        createInfo.ppEnabledLayerNames = validation_layers[0..].ptr;
    }

    var available_extensions_count: u32 = 0;
    result = vulkan.vkEnumerateInstanceExtensionProperties(null, &available_extensions_count, null);
    if (result != vulkan.VK_SUCCESS) unreachable;
    var available_extensions = try allocator_.alloc(vulkan.VkExtensionProperties, available_extensions_count);
    defer allocator_.free(available_extensions);
    result = vulkan.vkEnumerateInstanceExtensionProperties(null, &available_extensions_count, available_extensions.ptr);
    if (result != vulkan.VK_SUCCESS and result != vulkan.VK_INCOMPLETE) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            vulkan.VK_ERROR_LAYER_NOT_PRESENT => return VulkanError.vk_error_layer_not_present,
            else => unreachable,
        }
    }

    std.log.info("{d} available extensions:", .{available_extensions_count});
    for (available_extensions) |extension| {
        std.log.info("\t{s}", .{extension.extensionName});
    }

    const required_extensions = try get_required_extensions(allocator_);
    defer required_extensions.deinit();

    createInfo.flags |= vulkan.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;

    createInfo.enabledExtensionCount = @intCast(required_extensions.items.len);
    createInfo.ppEnabledExtensionNames = required_extensions.items.ptr;

    // ---

    var debug_create_info = DebugMessenger.empty_debug_messenger_create_info();
    if (enable_validation_layers) {
        createInfo.enabledLayerCount = validation_layers.len;
        createInfo.ppEnabledLayerNames = validation_layers[0..].ptr;

        debug_create_info = DebugMessenger.populated_debug_messenger_create_info();
        debug_create_info.pNext = @ptrCast(&debug_create_info);
    }

    // ---

    var vk_instance: vulkan.VkInstance = null;
    result = vulkan.vkCreateInstance(&createInfo, null, &vk_instance);
    if (result != vulkan.VK_SUCCESS) {
        return VulkanError.instance_init_failed;
    }

    return vk_instance;
}

fn create_surface(instance: vulkan.VkInstance, window: *glfw.GLFWwindow) VulkanError!vulkan.VkSurfaceKHR {
    var surface: vulkan.VkSurfaceKHR = null;

    const result = glfw.glfwCreateWindowSurface(@ptrCast(instance), window, null, @ptrCast(&surface));
    if (result != vulkan.VK_SUCCESS) {
        return VulkanError.surface_creation_failed;
    }

    return surface;
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

pub fn find_queue_families(physical_device: vulkan.VkPhysicalDevice, allocator_: std.mem.Allocator, surface: vulkan.VkSurfaceKHR) VulkanError!QueueFamilyIndices {
    var indices = QueueFamilyIndices.init_null();

    var queue_family_count: u32 = 0;
    vulkan.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, null);
    var queue_families = try allocator_.alloc(vulkan.VkQueueFamilyProperties, queue_family_count);
    defer allocator_.free(queue_families);
    vulkan.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, queue_families.ptr);

    var i: u32 = 0;
    while (i < queue_family_count) : (i += 1) {
        if (indices.is_complete()) break;

        const queue_family = queue_families[i];

        if (queue_family.queueFlags & vulkan.VK_QUEUE_GRAPHICS_BIT != 0) {
            indices.graphics_family = i;
        }

        var present_support = vulkan.VK_FALSE;
        const result = vulkan.vkGetPhysicalDeviceSurfaceSupportKHR(physical_device, i, surface, &present_support);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                vulkan.VK_ERROR_SURFACE_LOST_KHR => return VulkanError.vk_error_surface_lost_khr,
                else => unreachable,
            }
        }

        if (present_support == vulkan.VK_TRUE) {
            indices.present_family = i;
        }
    }

    return indices;
}

fn is_device_suitable(device: vulkan.VkPhysicalDevice, allocator_: std.mem.Allocator, surface: vulkan.VkSurfaceKHR) VulkanError!bool {
    const indices = try find_queue_families(device, allocator_, surface);

    const extensions_supported = try check_device_extension_support(device, allocator_);

    var swapchain_supported = false;
    if (extensions_supported) {
        const swapchain_support = try Swapchain.query_swapchain_support(allocator_, device, surface);
        defer swapchain_support.formats.deinit();
        defer swapchain_support.present_modes.deinit();
        swapchain_supported = swapchain_support.formats.items.len > 0 and swapchain_support.present_modes.items.len > 0;
    }

    return indices.is_complete() and extensions_supported and swapchain_supported;
}

fn check_device_extension_support(device: vulkan.VkPhysicalDevice, allocator_: std.mem.Allocator) VulkanError!bool {
    var extension_count: u32 = 0;
    var result = vulkan.vkEnumerateDeviceExtensionProperties(device, null, &extension_count, null);
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }

    var available_extensions = try allocator_.alloc(vulkan.VkExtensionProperties, extension_count);
    defer allocator_.free(available_extensions);
    result = vulkan.vkEnumerateDeviceExtensionProperties(device, null, &extension_count, available_extensions.ptr);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            vulkan.VK_ERROR_INITIALIZATION_FAILED => return VulkanError.vk_error_initialization_failed,
            else => unreachable,
        }
    }

    var found_exensions: usize = 0;
    for (device_extensions) |extension| {
        var found = false;
        for (available_extensions) |available_extension| {
            // Manual strcmp.
            var i: usize = 0;
            while (true) : (i += 1) {
                if (available_extension.extensionName[i] == 0 or i >= vulkan.VK_MAX_EXTENSION_NAME_SIZE) {
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

fn pick_physical_device(instance: vulkan.VkInstance, allocator_: std.mem.Allocator, surface: vulkan.VkSurfaceKHR) VulkanError!vulkan.VkPhysicalDevice {
    var device_count: u32 = 0;
    var result = vulkan.vkEnumeratePhysicalDevices(instance, &device_count, null);
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }

    if (device_count == 0) {
        return VulkanError.no_suitable_gpu;
    }

    var devices = try allocator_.alloc(vulkan.VkPhysicalDevice, device_count);
    defer allocator_.free(devices);
    result = vulkan.vkEnumeratePhysicalDevices(instance, &device_count, devices.ptr);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            vulkan.VK_ERROR_INITIALIZATION_FAILED => return VulkanError.vk_error_initialization_failed,

            else => unreachable,
        }
    }

    var selected_device: ?vulkan.VkPhysicalDevice = null;

    std.log.info("{d} devices found:", .{device_count});
    for (devices) |device| {
        var device_properties: vulkan.VkPhysicalDeviceProperties = undefined;
        vulkan.vkGetPhysicalDeviceProperties(device, &device_properties);

        var device_was_selected = false;

        if (selected_device == null) {
            const suitable = try is_device_suitable(device, allocator_, surface);
            if (suitable) {
                selected_device = device;
                device_was_selected = true;
            }
        }

        if (device_was_selected) {
            std.log.info("\t{s} (selected)", .{device_properties.deviceName});
        } else {
            std.log.info("\t{s}", .{device_properties.deviceName});
        }
    }

    if (selected_device == null) {
        return VulkanError.no_suitable_gpu;
    }

    return selected_device.?;
}

fn create_logical_device(physical_device: vulkan.VkPhysicalDevice, allocator_: std.mem.Allocator, surface: vulkan.VkSurfaceKHR) VulkanError!vulkan.VkDevice {
    const queue_family_indices = try find_queue_families(physical_device, allocator_, surface);

    var queue_create_infos = std.ArrayList(vulkan.VkDeviceQueueCreateInfo).init(allocator_);
    defer queue_create_infos.deinit();
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

    const queue_priority: f32 = 1.0;
    for (unique_queue_families.items) |queue_family| {
        var queue_create_info: vulkan.VkDeviceQueueCreateInfo = .{
            .sType = vulkan.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = queue_family,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
            .pNext = null,
            .flags = 0,
        };

        try queue_create_infos.append(queue_create_info);
    }

    const device_features: vulkan.VkPhysicalDeviceFeatures = .{
        .robustBufferAccess = vulkan.VK_FALSE,
        .fullDrawIndexUint32 = vulkan.VK_FALSE,
        .imageCubeArray = vulkan.VK_FALSE,
        .independentBlend = vulkan.VK_FALSE,
        .geometryShader = vulkan.VK_FALSE,
        .tessellationShader = vulkan.VK_FALSE,
        .sampleRateShading = vulkan.VK_FALSE,
        .dualSrcBlend = vulkan.VK_FALSE,
        .logicOp = vulkan.VK_FALSE,
        .multiDrawIndirect = vulkan.VK_FALSE,
        .drawIndirectFirstInstance = vulkan.VK_FALSE,
        .depthClamp = vulkan.VK_FALSE,
        .depthBiasClamp = vulkan.VK_FALSE,
        .fillModeNonSolid = vulkan.VK_FALSE,
        .depthBounds = vulkan.VK_FALSE,
        .wideLines = vulkan.VK_FALSE,
        .largePoints = vulkan.VK_FALSE,
        .alphaToOne = vulkan.VK_FALSE,
        .multiViewport = vulkan.VK_FALSE,
        .samplerAnisotropy = vulkan.VK_FALSE,
        .textureCompressionETC2 = vulkan.VK_FALSE,
        .textureCompressionASTC_LDR = vulkan.VK_FALSE,
        .textureCompressionBC = vulkan.VK_FALSE,
        .occlusionQueryPrecise = vulkan.VK_FALSE,
        .pipelineStatisticsQuery = vulkan.VK_FALSE,
        .vertexPipelineStoresAndAtomics = vulkan.VK_FALSE,
        .fragmentStoresAndAtomics = vulkan.VK_FALSE,
        .shaderTessellationAndGeometryPointSize = vulkan.VK_FALSE,
        .shaderImageGatherExtended = vulkan.VK_FALSE,
        .shaderStorageImageExtendedFormats = vulkan.VK_FALSE,
        .shaderStorageImageMultisample = vulkan.VK_FALSE,
        .shaderStorageImageReadWithoutFormat = vulkan.VK_FALSE,
        .shaderStorageImageWriteWithoutFormat = vulkan.VK_FALSE,
        .shaderUniformBufferArrayDynamicIndexing = vulkan.VK_FALSE,
        .shaderSampledImageArrayDynamicIndexing = vulkan.VK_FALSE,
        .shaderStorageBufferArrayDynamicIndexing = vulkan.VK_FALSE,
        .shaderStorageImageArrayDynamicIndexing = vulkan.VK_FALSE,
        .shaderClipDistance = vulkan.VK_FALSE,
        .shaderCullDistance = vulkan.VK_FALSE,
        .shaderFloat64 = vulkan.VK_FALSE,
        .shaderInt64 = vulkan.VK_FALSE,
        .shaderInt16 = vulkan.VK_FALSE,
        .shaderResourceResidency = vulkan.VK_FALSE,
        .shaderResourceMinLod = vulkan.VK_FALSE,
        .sparseBinding = vulkan.VK_FALSE,
        .sparseResidencyBuffer = vulkan.VK_FALSE,
        .sparseResidencyImage2D = vulkan.VK_FALSE,
        .sparseResidencyImage3D = vulkan.VK_FALSE,
        .sparseResidency2Samples = vulkan.VK_FALSE,
        .sparseResidency4Samples = vulkan.VK_FALSE,
        .sparseResidency8Samples = vulkan.VK_FALSE,
        .sparseResidency16Samples = vulkan.VK_FALSE,
        .sparseResidencyAliased = vulkan.VK_FALSE,
        .variableMultisampleRate = vulkan.VK_FALSE,
        .inheritedQueries = vulkan.VK_FALSE,
    };

    var create_info: vulkan.VkDeviceCreateInfo = .{
        .sType = vulkan.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = @intCast(queue_create_infos.items.len),
        .pQueueCreateInfos = queue_create_infos.items.ptr,
        .pEnabledFeatures = &device_features,
        .pNext = null,
        .flags = 0,

        // To be changed.
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
        .enabledExtensionCount = @intCast(device_extensions.len),
        .ppEnabledExtensionNames = device_extensions[0..].ptr,
    };

    if (enable_validation_layers) {
        create_info.enabledLayerCount = validation_layers.len;
        create_info.ppEnabledLayerNames = validation_layers[0..].ptr;
    }

    var logical_device: vulkan.VkDevice = undefined;
    const result = vulkan.vkCreateDevice(physical_device, &create_info, null, &logical_device);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            vulkan.VK_ERROR_INITIALIZATION_FAILED => return VulkanError.vk_error_initialization_failed,
            vulkan.VK_ERROR_EXTENSION_NOT_PRESENT => return VulkanError.vk_error_extension_not_present,
            vulkan.VK_ERROR_FEATURE_NOT_PRESENT => return VulkanError.vk_error_feature_not_present,
            vulkan.VK_ERROR_TOO_MANY_OBJECTS => return VulkanError.vk_error_too_many_objects,
            vulkan.VK_ERROR_DEVICE_LOST => return VulkanError.vk_error_device_lost,
            else => unreachable,
        }
    }

    return logical_device;
}

fn check_validation_layer_support(allocator_: std.mem.Allocator) VulkanError!bool {
    var available_layers_count: u32 = 0;
    var result = vulkan.vkEnumerateInstanceLayerProperties(&available_layers_count, null);
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }

    var available_layers = try allocator_.alloc(vulkan.VkLayerProperties, available_layers_count);
    defer allocator_.free(available_layers);
    result = vulkan.vkEnumerateInstanceLayerProperties(&available_layers_count, available_layers.ptr);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return error.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return error.vk_error_out_of_device_memory,
            else => unreachable,
        }
    }

    var i: usize = 0;
    for (validation_layers) |layer_name| {
        var layer_found = false;

        while (i < available_layers_count) : (i += 1) {
            const s1 = available_layers[i].layerName;
            const s2 = layer_name;

            // Manual strcmp.
            var j: usize = 0;
            while (j < vulkan.VK_MAX_EXTENSION_NAME_SIZE) : (j += 1) {
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

fn get_required_extensions(allocator_: std.mem.Allocator) VulkanError!std.ArrayList([*c]const u8) {
    var glfwExtensionCount: u32 = 0;
    const glfwExtensions = glfw.glfwGetRequiredInstanceExtensions(&glfwExtensionCount);

    var extensions = std.ArrayList([*c]const u8).init(allocator_);
    var i: usize = 0;
    while (i < glfwExtensionCount) : (i += 1) {
        try extensions.append(glfwExtensions[i]);
    }

    if (enable_validation_layers) {
        try extensions.append(vulkan.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
    }

    try extensions.append(vulkan.VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME);
    try extensions.append(vulkan.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);

    return extensions;
}

fn create_render_pass(device: vulkan.VkDevice, swap_chain_image_format: vulkan.VkFormat) VulkanError!vulkan.VkRenderPass {
    const color_attachment = vulkan.VkAttachmentDescription{
        .format = swap_chain_image_format,
        .samples = vulkan.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = vulkan.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = vulkan.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = vulkan.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = vulkan.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = vulkan.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = vulkan.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,

        .flags = 0,
    };

    // --- Subpass.

    const color_attachment_ref = vulkan.VkAttachmentReference{
        .attachment = 0,
        .layout = vulkan.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    const subpass = vulkan.VkSubpassDescription{
        .pipelineBindPoint = vulkan.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment_ref,

        .flags = 0,
        .inputAttachmentCount = 0,
        .pInputAttachments = null,
        .pResolveAttachments = null,
        .pDepthStencilAttachment = null,
        .preserveAttachmentCount = 0,
        .pPreserveAttachments = null,
    };

    // --- Subpass dependencies.

    const subpass_dependency = vulkan.VkSubpassDependency{
        .srcSubpass = vulkan.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = vulkan.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstStageMask = vulkan.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask = vulkan.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,

        .dependencyFlags = 0,
    };

    // ---

    const render_pass_info = vulkan.VkRenderPassCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &color_attachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,

        .dependencyCount = 1,
        .pDependencies = &subpass_dependency,
        .flags = 0,
        .pNext = null,
    };

    var render_pass: vulkan.VkRenderPass = undefined;
    const result = vulkan.vkCreateRenderPass(device, &render_pass_info, null, &render_pass);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            else => unreachable,
        }
    }

    return render_pass;
}

fn create_command_pool(allocator_: std.mem.Allocator, physical_device: vulkan.VkPhysicalDevice, logical_device: vulkan.VkDevice, surface: vulkan.VkSurfaceKHR) VulkanError!vulkan.VkCommandPool {
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

fn create_command_buffers(
    allocator_: std.mem.Allocator,
    logical_device: vulkan.VkDevice,
    command_pool: vulkan.VkCommandPool,
) VulkanError![]vulkan.VkCommandBuffer {
    const command_buffers = try allocator_.alloc(vulkan.VkCommandBuffer, max_frames_in_flight);
    errdefer allocator_.free(command_buffers);

    const alloc_info = vulkan.VkCommandBufferAllocateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = vulkan.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = @intCast(command_buffers.len),

        .pNext = null,
    };

    const result = vulkan.vkAllocateCommandBuffers(logical_device, &alloc_info, command_buffers.ptr);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            else => unreachable,
        }
    }

    return command_buffers;
}

fn record_command_buffer(self: *VulkanSystem, command_buffer: vulkan.VkCommandBuffer, image_index: usize) VulkanError!void {
    // --- Begin command buffer.

    const begin_info = vulkan.VkCommandBufferBeginInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = 0,
        .pInheritanceInfo = null,
        .pNext = null,
    };

    var result = vulkan.vkBeginCommandBuffer(command_buffer, &begin_info);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            else => unreachable,
        }
    }

    // --- Begin render pass.

    const clear_color: vulkan.VkClearValue = .{
        .color = .{
            .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 },
        },
    };

    const render_pass_info = vulkan.VkRenderPassBeginInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = self.render_pass,
        .framebuffer = self.swapchain.framebuffers[image_index],
        .renderArea = vulkan.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain.swapchain_extent,
        },
        .clearValueCount = 1,
        .pClearValues = &clear_color,

        .pNext = null,
    };

    vulkan.vkCmdBeginRenderPass(command_buffer, &render_pass_info, vulkan.VK_SUBPASS_CONTENTS_INLINE);

    // --- Draw.

    vulkan.vkCmdBindPipeline(command_buffer, vulkan.VK_PIPELINE_BIND_POINT_GRAPHICS, self.graphics_pipeline.pipeline);

    const vertex_buffers = [_]vulkan.VkBuffer{self.vertex_buffer.vertex_buffer};
    const offsets = [_]vulkan.VkDeviceSize{0};
    vulkan.vkCmdBindVertexBuffers(command_buffer, 0, 1, vertex_buffers[0..].ptr, offsets[0..].ptr);

    const viewport = vulkan.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(self.swapchain.swapchain_extent.width),
        .height = @floatFromInt(self.swapchain.swapchain_extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    vulkan.vkCmdSetViewport(command_buffer, 0, 1, &viewport);

    const scissor = vulkan.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = self.swapchain.swapchain_extent,
    };
    vulkan.vkCmdSetScissor(command_buffer, 0, 1, &scissor);

    vulkan.vkCmdDraw(command_buffer, Vertex.vertices.len, 1, 0, 0);

    // --- End render pass.

    vulkan.vkCmdEndRenderPass(command_buffer);

    // --- End command buffer.

    result = vulkan.vkEndCommandBuffer(command_buffer);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            else => unreachable,
        }
    }
}

const CreateSyncObjectsReturnType = struct {
    image_available_semaphores: []vulkan.VkSemaphore,
    render_finished_semaphores: []vulkan.VkSemaphore,
    in_flight_fences: []vulkan.VkFence,
};

fn create_sync_objects(allocator_: std.mem.Allocator, device: vulkan.VkDevice) VulkanError!CreateSyncObjectsReturnType {
    var image_available_semaphores = try allocator_.alloc(vulkan.VkSemaphore, max_frames_in_flight);
    errdefer allocator_.free(image_available_semaphores);
    var render_finished_semaphores = try allocator_.alloc(vulkan.VkSemaphore, max_frames_in_flight);
    errdefer allocator_.free(render_finished_semaphores);
    var in_flight_fences = try allocator_.alloc(vulkan.VkFence, max_frames_in_flight);
    errdefer allocator_.free(in_flight_fences);

    var semaphore_info = vulkan.VkSemaphoreCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
    };

    var fence_info = vulkan.VkFenceCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .pNext = null,
        .flags = vulkan.VK_FENCE_CREATE_SIGNALED_BIT,
    };

    var i: usize = 0;
    while (i < max_frames_in_flight) : (i += 1) {
        var result = vulkan.vkCreateSemaphore(device, &semaphore_info, null, &image_available_semaphores[i]);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }
        errdefer vulkan.vkDestroySemaphore(device, image_available_semaphores[i], null);

        result = vulkan.vkCreateSemaphore(device, &semaphore_info, null, &render_finished_semaphores[i]);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }
        errdefer vulkan.vkDestroySemaphore(device, render_finished_semaphores[i], null);

        result = vulkan.vkCreateFence(device, &fence_info, null, &in_flight_fences[i]);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }
    }

    return .{
        .image_available_semaphores = image_available_semaphores,
        .render_finished_semaphores = render_finished_semaphores,
        .in_flight_fences = in_flight_fences,
    };
}

const VertexBuffer = struct {
    vertex_buffer: vulkan.VkBuffer,
    vertex_buffer_memory: vulkan.VkDeviceMemory,

    fn init(physical_device: vulkan.VkPhysicalDevice, device: vulkan.VkDevice) VulkanError!VertexBuffer {
        const buffer_info = vulkan.VkBufferCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = @sizeOf(Vertex.Vertex) * Vertex.vertices.len,
            .usage = vulkan.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            .sharingMode = vulkan.VK_SHARING_MODE_EXCLUSIVE,

            .pNext = null,
            .flags = 0,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        };

        var vertex_buffer: vulkan.VkBuffer = undefined;
        var result = vulkan.vkCreateBuffer(device, &buffer_info, null, &vertex_buffer);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS_KHR => return VulkanError.vk_error_invalid_opaque_capture_address_khr,
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }
        errdefer vulkan.vkDestroyBuffer(device, vertex_buffer, null);

        // --- Memory allocation.

        var memory_requirements: vulkan.VkMemoryRequirements = undefined;
        vulkan.vkGetBufferMemoryRequirements(device, vertex_buffer, &memory_requirements);

        const memory_type_index = try find_memory_type(
            physical_device,
            memory_requirements.memoryTypeBits,
            vulkan.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vulkan.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        );
        const alloc_info = vulkan.VkMemoryAllocateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = memory_requirements.size,
            .memoryTypeIndex = memory_type_index,

            .pNext = null,
        };

        var vertex_buffer_memory: vulkan.VkDeviceMemory = undefined;
        result = vulkan.vkAllocateMemory(device, &alloc_info, null, &vertex_buffer_memory);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }
        errdefer vulkan.vkFreeMemory(device, vertex_buffer_memory, null);

        // --- Bind memory.

        result = vulkan.vkBindBufferMemory(device, vertex_buffer, vertex_buffer_memory, 0);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }

        // --- Fill memory.

        var data: ?*anyopaque = undefined;
        result = vulkan.vkMapMemory(device, vertex_buffer_memory, 0, buffer_info.size, 0, &data);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }

        _ = c_string.memcpy(data, @ptrCast(Vertex.vertices[0..].ptr), @intCast(buffer_info.size));

        vulkan.vkUnmapMemory(device, vertex_buffer_memory);

        return VertexBuffer{
            .vertex_buffer = vertex_buffer,
            .vertex_buffer_memory = vertex_buffer_memory,
        };
    }

    fn deinit(self: VertexBuffer, device: vulkan.VkDevice) void {
        vulkan.vkDestroyBuffer(device, self.vertex_buffer, null);
        vulkan.vkFreeMemory(device, self.vertex_buffer_memory, null);
    }

    fn find_memory_type(physical_device: vulkan.VkPhysicalDevice, memory_type_filter: u32, properties: vulkan.VkMemoryPropertyFlags) VulkanError!u32 {
        var memory_properties: vulkan.VkPhysicalDeviceMemoryProperties = undefined;
        vulkan.vkGetPhysicalDeviceMemoryProperties(physical_device, &memory_properties);

        var i: u5 = 0;
        while (i < memory_properties.memoryTypeCount) : (i += 1) {
            if ((memory_type_filter & (@as(u32, @intCast(1)) << i) != 0) and (memory_properties.memoryTypes[i].propertyFlags & properties) == properties) {
                return i;
            }
        }

        return VulkanError.no_suitable_memory_type;
    }
};
