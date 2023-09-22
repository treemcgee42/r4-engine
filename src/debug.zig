const std = @import("std");
const vulkan = @import("c.zig").vulkan;

const VulkanError = @import("vulkan.zig").VulkanError;

const DebugMessenger = @This();

instance: vulkan.VkInstance,
debug_messenger: vulkan.VkDebugUtilsMessengerEXT,

pub fn init(instance: vulkan.VkInstance) VulkanError!DebugMessenger {
    var create_info = populated_debug_messenger_create_info();
    var debug_messenger: vulkan.VkDebugUtilsMessengerEXT = undefined;
    const result = try create_debug_utils_messenger_ext(instance, &create_info, null, &debug_messenger);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            else => unreachable,
        }
    }

    return .{
        .instance = instance,
        .debug_messenger = debug_messenger,
    };
}

pub fn deinit(self: *DebugMessenger) void {
    destroy_debug_utils_messenger_ext(self.instance, self.debug_messenger, null);
}

const debug_callback_return_ty = vulkan.VkBool32;

fn debug_callback(
    message_severity: vulkan.VkDebugUtilsMessageSeverityFlagBitsEXT,
    message_type: vulkan.VkDebugUtilsMessageTypeFlagsEXT,
    p_callback_data: [*c]const vulkan.VkDebugUtilsMessengerCallbackDataEXT,
    p_user_data: ?*anyopaque,
) callconv(.C) debug_callback_return_ty {
    _ = p_user_data;
    _ = message_type;
    _ = message_severity;

    std.debug.print("validation layer: {s}\n", .{p_callback_data.*.pMessage});

    return vulkan.VK_FALSE;
}

fn create_debug_utils_messenger_ext(
    instance: vulkan.VkInstance,
    p_create_info: *const vulkan.VkDebugUtilsMessengerCreateInfoEXT,
    p_allocator: ?*const vulkan.VkAllocationCallbacks,
    p_debug_messenger: *vulkan.VkDebugUtilsMessengerEXT,
) error{vk_error_extension_not_present}!vulkan.VkResult {
    const func: vulkan.PFN_vkCreateDebugUtilsMessengerEXT = @ptrCast(vulkan.vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"));
    if (func != null) {
        return @call(.auto, func.?, .{ instance, p_create_info, p_allocator, p_debug_messenger });
    }

    return VulkanError.vk_error_extension_not_present;
}

fn destroy_debug_utils_messenger_ext(
    instance: vulkan.VkInstance,
    debug_messenger: vulkan.VkDebugUtilsMessengerEXT,
    p_allocator: ?*const vulkan.VkAllocationCallbacks,
) void {
    const func: vulkan.PFN_vkDestroyDebugUtilsMessengerEXT = @ptrCast(vulkan.vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"));
    if (func != null) {
        return @call(.auto, func.?, .{ instance, debug_messenger, p_allocator });
    }
}

pub fn empty_debug_messenger_create_info() vulkan.VkDebugUtilsMessengerCreateInfoEXT {
    return .{
        .sType = 0,
        .messageSeverity = 0,
        .messageType = 0,
        .pfnUserCallback = null,
        .pUserData = null,
        .pNext = null,
        .flags = 0,
    };
}

pub fn populated_debug_messenger_create_info() vulkan.VkDebugUtilsMessengerCreateInfoEXT {
    return .{
        .sType = vulkan.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        .messageSeverity = vulkan.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | vulkan.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | vulkan.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
        .messageType = vulkan.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | vulkan.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | vulkan.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
        .pfnUserCallback = debug_callback,
        .pUserData = null,
        .pNext = null,
        .flags = 0,
    };
}
