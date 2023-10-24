const std = @import("std");
const vulkan = @import("vulkan");

pub usingnamespace @import("./memory.zig");
pub usingnamespace @import("./startup.zig");
pub usingnamespace @import("./surface.zig");
pub usingnamespace @import("./queue.zig");
pub usingnamespace @import("./command.zig");
pub usingnamespace @import("./sync.zig");
pub usingnamespace @import("./pipeline.zig");

// ---

pub const VkExtent2D = vulkan.VkExtent2D;
pub const VkExtent3D = vulkan.VkExtent3D;

// ---

pub const VkLayerProperties = vulkan.VkLayerProperties;
pub const VK_MAX_EXTENSION_NAME_SIZE = vulkan.VK_MAX_EXTENSION_NAME_SIZE;

pub const vkEnumerateInstanceLayerPropertiesError = error{
    VK_INCOMPLETE,
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,

    OutOfMemory,
};

pub fn vkEnumerateInstanceLayerProperties(
    allocator: std.mem.Allocator,
) vkEnumerateInstanceLayerPropertiesError![]VkLayerProperties {
    var available_layers_count: u32 = 0;
    var result = vulkan.vkEnumerateInstanceLayerProperties(
        &available_layers_count,
        null,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_INCOMPLETE => return vkEnumerateInstanceLayerPropertiesError.VK_INCOMPLETE,
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkEnumerateInstanceLayerPropertiesError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkEnumerateInstanceLayerPropertiesError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            else => unreachable,
        }
    }

    var available_layers = try allocator.alloc(
        vulkan.VkLayerProperties,
        available_layers_count,
    );
    errdefer allocator.free(available_layers);
    result = vulkan.vkEnumerateInstanceLayerProperties(
        &available_layers_count,
        available_layers.ptr,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_INCOMPLETE => return vkEnumerateInstanceLayerPropertiesError.VK_INCOMPLETE,
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkEnumerateInstanceLayerPropertiesError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkEnumerateInstanceLayerPropertiesError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            else => unreachable,
        }
    }

    return available_layers;
}

// ---

pub const VkSharingMode = enum(c_uint) {
    exclusive = 0,
    concurrent = 1,

    max_enum = 2147483647,
};

// ---

pub const VkQueryControlFlags = packed struct(u32) {
    precise: bool = false,
    _: u3 = 0,

    _a: u28 = 0,

    pub const Bits = enum(c_uint) {
        precise = 0x00000001,
    };
};

// ---

pub const VkRenderPass = vulkan.VkRenderPass;

pub const VkFramebuffer = vulkan.VkFramebuffer;

// --- pipeline
