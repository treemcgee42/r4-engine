const std = @import("std");
const builtin = @import("builtin");

const vulkan = @import("c.zig").vulkan;
const glfw = @import("c.zig").glfw;

const DebugMessenger = @import("debug.zig");

const VulkanSystem = @This();

allocator: std.mem.Allocator,

instance: vulkan.VkInstance,
debug_messenger: ?DebugMessenger,

pub const VulkanError = error{
    validation_layer_not_present,
    instance_init_failed,

    vk_error_out_of_host_memory,
    vk_error_out_of_device_memory,
    vk_error_extension_not_present,
    vk_error_layer_not_present,
} || std.mem.Allocator.Error;

const enable_validation_layers = (builtin.mode == .Debug);
const validation_layers = [_][*c]const u8{
    "VK_LAYER_KHRONOS_validation",
};

pub fn init(allocator_: std.mem.Allocator) VulkanError!VulkanSystem {
    const instance = try create_vulkan_instance(allocator_);
    var debug_messenger: ?DebugMessenger = null;
    if (enable_validation_layers) {
        debug_messenger = try DebugMessenger.init(instance);
    }

    return VulkanSystem{
        .allocator = allocator_,

        .instance = instance,
        .debug_messenger = debug_messenger,
    };
}

pub fn deinit(self: *VulkanSystem) void {
    if (enable_validation_layers) {
        self.debug_messenger.?.deinit();
    }

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
    if (result != vulkan.VK_SUCCESS and result != vulkan.VK_INCOMPLETE) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            vulkan.VK_ERROR_LAYER_NOT_PRESENT => return VulkanError.vk_error_layer_not_present,
            else => unreachable,
        }
    }
    std.debug.print("{d} available extensions.\n", .{available_extensions_count});

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
            std.debug.print("couldn't find validation layer {s}\n", .{layer_name});
            return false;
        }

        std.debug.print("found validation layer {s}\n", .{layer_name});
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
