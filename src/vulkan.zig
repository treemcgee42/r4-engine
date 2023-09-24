const std = @import("std");
const builtin = @import("builtin");

const vulkan = @import("c.zig").vulkan;
const glfw = @import("c.zig").glfw;

const DebugMessenger = @import("debug.zig");

const VulkanSystem = @This();

allocator: std.mem.Allocator,

instance: vulkan.VkInstance,
debug_messenger: ?DebugMessenger,

surface: vulkan.VkSurfaceKHR,

physical_device: vulkan.VkPhysicalDevice,
logical_device: vulkan.VkDevice,

graphics_queue: vulkan.VkQueue,
present_queue: vulkan.VkQueue,

pub const VulkanError = error{
    validation_layer_not_present,
    instance_init_failed,
    no_suitable_gpu,
    surface_creation_failed,

    vk_error_out_of_host_memory,
    vk_error_out_of_device_memory,
    vk_error_extension_not_present,
    vk_error_layer_not_present,
    vk_error_initialization_failed,
    vk_error_feature_not_present,
    vk_error_too_many_objects,
    vk_error_device_lost,
    vk_error_surface_lost_khr,
} || std.mem.Allocator.Error;

const enable_validation_layers = (builtin.mode == .Debug);
const validation_layers = [_][*c]const u8{
    "VK_LAYER_KHRONOS_validation",
};

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

    return VulkanSystem{
        .allocator = allocator_,

        .instance = instance,
        .debug_messenger = debug_messenger,

        .surface = surface,

        .physical_device = physical_device,
        .logical_device = logical_device,

        .graphics_queue = graphics_queue,
        .present_queue = present_queue,
    };
}

pub fn deinit(self: *VulkanSystem) void {
    vulkan.vkDestroyDevice(self.logical_device, null);

    if (enable_validation_layers) {
        self.debug_messenger.?.deinit();
    }

    vulkan.vkDestroySurfaceKHR(self.instance, self.surface, null);
    vulkan.vkDestroyInstance(self.instance, null);
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

fn find_queue_families(physical_device: vulkan.VkPhysicalDevice, allocator_: std.mem.Allocator, surface: vulkan.VkSurfaceKHR) VulkanError!QueueFamilyIndices {
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

    return indices.is_complete();
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
        .enabledExtensionCount = 0,
        .ppEnabledExtensionNames = null,
    };

    var enabled_extensions = [_][*:0]const u8{"VK_KHR_portability_subset"};
    create_info.enabledExtensionCount = enabled_extensions.len;
    create_info.ppEnabledExtensionNames = enabled_extensions[0..].ptr;

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
