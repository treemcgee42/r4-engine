const std = @import("std");
const builtin = @import("builtin");
const vulkan = @import("../../c/vulkan.zig");
const glfw = @import("../../c/glfw.zig");
const DebugMessenger = @import("./DebugMessenger.zig");
const PipelineSystem = @import("./PipelineSystem.zig");

const VulkanSystem = @This();

instance: vulkan.VkInstance,
debug_messenger: ?DebugMessenger,

physical_device: vulkan.VkPhysicalDevice,
support_details: SwapchainSupportDetails,
logical_device: vulkan.VkDevice,

graphics_queue: vulkan.VkQueue,
present_queue: vulkan.VkQueue,

command_pool: vulkan.VkCommandPool,
command_buffers: []vulkan.VkCommandBuffer,

pipeline_system: PipelineSystem,

max_usable_sample_count: vulkan.VkSampleCountFlagBits,

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

pub fn init(allocator_: std.mem.Allocator) VulkanError!VulkanSystem {
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
    const command_buffers = try create_command_buffers(allocator_, logical_device, command_pool);

    const pipeline_system = try PipelineSystem.init(allocator_);

    // ---

    const max_usable_sample_count = try get_max_usable_sample_count(physical_device);

    // ---

    return .{
        .instance = instance,
        .debug_messenger = debug_messenger,

        .physical_device = physical_device,
        .support_details = support_details,
        .logical_device = logical_device,

        .graphics_queue = graphics_queue,
        .present_queue = present_queue,

        .command_pool = command_pool,
        .command_buffers = command_buffers,

        .pipeline_system = pipeline_system,

        .max_usable_sample_count = max_usable_sample_count,
    };
}

pub fn deinit(self: *VulkanSystem, allocator_: std.mem.Allocator) void {
    self.support_details.deinit(allocator_);

    self.pipeline_system.deinit(self.logical_device);

    vulkan.vkDestroyCommandPool(self.logical_device, self.command_pool, null);
    allocator_.free(self.command_buffers);

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

// --- }}}1

pub fn create_surface(instance: vulkan.VkInstance, window: *glfw.GLFWwindow) VulkanError!vulkan.VkSurfaceKHR {
    var surface: vulkan.VkSurfaceKHR = null;

    const result = glfw.glfwCreateWindowSurface(@ptrCast(instance), window, null, @ptrCast(&surface));
    if (result != vulkan.VK_SUCCESS) {
        return VulkanError.surface_creation_failed;
    }

    return surface;
}

// --- Physical Device {{{1

fn pick_physical_device(
    instance: vulkan.VkInstance,
    allocator_: std.mem.Allocator,
    surface: vulkan.VkSurfaceKHR,
) VulkanError!vulkan.VkPhysicalDevice {
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

fn is_device_suitable(
    device: vulkan.VkPhysicalDevice,
    allocator_: std.mem.Allocator,
    surface: vulkan.VkSurfaceKHR,
) VulkanError!bool {
    const indices = try find_queue_families(device, allocator_, surface);

    const extensions_supported = try check_device_extension_support(device, allocator_);

    var swapchain_supported = false;
    if (extensions_supported) {
        var swapchain_support = try SwapchainSupportDetails.init(allocator_, device, surface);
        defer swapchain_support.deinit(allocator_);
        swapchain_supported = swapchain_support.formats.len > 0 and swapchain_support.present_modes.len > 0;
    }

    var supported_features: vulkan.VkPhysicalDeviceFeatures = undefined;
    vulkan.vkGetPhysicalDeviceFeatures(device, &supported_features);

    return indices.is_complete() and extensions_supported and swapchain_supported and (supported_features.samplerAnisotropy == vulkan.VK_TRUE);
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
    physical_device: vulkan.VkPhysicalDevice,
    allocator_: std.mem.Allocator,
    surface: vulkan.VkSurfaceKHR,
) VulkanError!QueueFamilyIndices {
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

fn get_max_usable_sample_count(physical_device: vulkan.VkPhysicalDevice) VulkanError!vulkan.VkSampleCountFlagBits {
    var physical_device_properties: vulkan.VkPhysicalDeviceProperties = undefined;
    vulkan.vkGetPhysicalDeviceProperties(physical_device, &physical_device_properties);

    const counts = physical_device_properties.limits.framebufferColorSampleCounts &
        physical_device_properties.limits.framebufferDepthSampleCounts;

    if (counts & vulkan.VK_SAMPLE_COUNT_64_BIT != 0) {
        return vulkan.VK_SAMPLE_COUNT_64_BIT;
    }
    if (counts & vulkan.VK_SAMPLE_COUNT_32_BIT != 0) {
        return vulkan.VK_SAMPLE_COUNT_32_BIT;
    }
    if (counts & vulkan.VK_SAMPLE_COUNT_16_BIT != 0) {
        return vulkan.VK_SAMPLE_COUNT_16_BIT;
    }
    if (counts & vulkan.VK_SAMPLE_COUNT_8_BIT != 0) {
        return vulkan.VK_SAMPLE_COUNT_8_BIT;
    }
    if (counts & vulkan.VK_SAMPLE_COUNT_4_BIT != 0) {
        return vulkan.VK_SAMPLE_COUNT_4_BIT;
    }
    if (counts & vulkan.VK_SAMPLE_COUNT_2_BIT != 0) {
        return vulkan.VK_SAMPLE_COUNT_2_BIT;
    }

    return vulkan.VK_SAMPLE_COUNT_1_BIT;
}

// --- }}}1

// --- Logical Device {{{1

fn create_logical_device(
    physical_device: vulkan.VkPhysicalDevice,
    allocator_: std.mem.Allocator,
    surface: vulkan.VkSurfaceKHR,
) VulkanError!vulkan.VkDevice {
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
        .samplerAnisotropy = vulkan.VK_TRUE,

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

// --- }}}1

// --- Swapchain support {{{1

pub const SwapchainSupportDetails = struct {
    capabilities: vulkan.VkSurfaceCapabilitiesKHR,
    formats: []vulkan.VkSurfaceFormatKHR,
    present_modes: []vulkan.VkPresentModeKHR,

    pub fn init(
        allocator_: std.mem.Allocator,
        physical_device: vulkan.VkPhysicalDevice,
        surface: vulkan.VkSurfaceKHR,
    ) VulkanError!SwapchainSupportDetails {
        var capabilities: vulkan.VkSurfaceCapabilitiesKHR = undefined;
        var formats: []vulkan.VkSurfaceFormatKHR = undefined;
        var present_modes: []vulkan.VkPresentModeKHR = undefined;

        var result = vulkan.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &capabilities);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                vulkan.VK_ERROR_SURFACE_LOST_KHR => return VulkanError.vk_error_surface_lost_khr,
                else => unreachable,
            }
        }

        // --- Format modes.

        var format_count: u32 = undefined;
        result = vulkan.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, null);
        if (result != vulkan.VK_SUCCESS) {
            unreachable;
        }
        if (format_count != 0) {
            formats = try allocator_.alloc(vulkan.VkSurfaceFormatKHR, format_count);
            result = vulkan.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, formats.ptr);
            if (result != vulkan.VK_SUCCESS and result != vulkan.VK_INCOMPLETE) {
                switch (result) {
                    vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                    vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                    vulkan.VK_ERROR_SURFACE_LOST_KHR => return VulkanError.vk_error_surface_lost_khr,
                    else => unreachable,
                }
            }
        }

        // --- Present modes.

        var present_mode_count: u32 = undefined;
        result = vulkan.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, null);
        if (result != vulkan.VK_SUCCESS) {
            unreachable;
        }
        if (present_mode_count != 0) {
            present_modes = try allocator_.alloc(vulkan.VkPresentModeKHR, present_mode_count);
            result = vulkan.vkGetPhysicalDeviceSurfacePresentModesKHR(
                physical_device,
                surface,
                &present_mode_count,
                present_modes.ptr,
            );
            if (result != vulkan.VK_SUCCESS) {
                switch (result) {
                    vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                    vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                    vulkan.VK_ERROR_SURFACE_LOST_KHR => return VulkanError.vk_error_surface_lost_khr,
                    else => unreachable,
                }
            }
        }

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
    surface_format: vulkan.VkSurfaceFormatKHR,
    present_mode: vulkan.VkPresentModeKHR,
    extent: vulkan.VkExtent2D,
    min_image_count: u32,
    // Right now, we only support up to two distinct queue families,
    // which should only be the case if the graphics and present
    // queues are distinct.
    image_sharing_mode: vulkan.VkSharingMode,
    queue_family_index_count: u32,
    queue_family_indices: [2]u32,

    capabilities: vulkan.VkSurfaceCapabilitiesKHR,

    logical_device: vulkan.VkDevice,
    surface: vulkan.VkSurfaceKHR,
};

/// We abstract this because the renderpass might like to know some of this information.
/// By passing the same info to both the renderpass and swapchain, we can ensure the
/// objects are created with the same attributes, for example.
pub fn query_swapchain_settings(
    allocator_: std.mem.Allocator,
    physical_device: vulkan.VkPhysicalDevice,
    logical_device: vulkan.VkDevice,
    surface: vulkan.VkSurfaceKHR,
) VulkanError!SwapchainSettings {
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

fn choose_swap_surface_format(available_formats: []const vulkan.VkSurfaceFormatKHR) vulkan.VkSurfaceFormatKHR {
    for (available_formats) |available_format| {
        if (available_format.format == vulkan.VK_FORMAT_B8G8R8A8_SRGB and available_format.colorSpace == vulkan.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return available_format;
        }
    }

    return available_formats[0];
}

fn choose_swap_chain_present_mode(available_present_modes: []const vulkan.VkPresentModeKHR) vulkan.VkPresentModeKHR {
    for (available_present_modes) |available_present_mode| {
        if (available_present_mode == vulkan.VK_PRESENT_MODE_MAILBOX_KHR) {
            return available_present_mode;
        }
    }

    return vulkan.VK_PRESENT_MODE_FIFO_KHR;
}

fn choose_swap_extent(capabilities: vulkan.VkSurfaceCapabilitiesKHR) vulkan.VkExtent2D {
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    } else {
        const width = @as(u32, @intCast(glfw.glfwGetVideoMode(glfw.glfwGetPrimaryMonitor()).*.width));
        const height = @as(u32, @intCast(glfw.glfwGetVideoMode(glfw.glfwGetPrimaryMonitor()).*.height));

        var actual_extent = vulkan.VkExtent2D{
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
) VulkanError!vulkan.VkCommandPool {
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
// --- }}}1
