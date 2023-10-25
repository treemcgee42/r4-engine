const std = @import("std");
const vulkan = @import("vulkan");

pub usingnamespace @import("./memory.zig");
pub usingnamespace @import("./startup.zig");
pub usingnamespace @import("./surface.zig");
pub usingnamespace @import("./queue.zig");
pub usingnamespace @import("./command.zig");
pub usingnamespace @import("./sync.zig");
pub usingnamespace @import("./pipeline.zig");
pub usingnamespace @import("./image.zig");

const l0vk = @This();

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

// --- swapchain

pub const VkSwapchainKHR = vulkan.VkSwapchainKHR;

pub inline fn vkDestroySwapchainKHR(
    device: l0vk.VkDevice,
    swapchain: VkSwapchainKHR,
    pAllocator: [*c]const l0vk.VkAllocationCallbacks,
) void {
    vulkan.vkDestroySwapchainKHR(device, swapchain, pAllocator);
}

pub const VkSwapchainCreateFlagsKHR = packed struct(u32) {
    split_instance_bind_regions: bool = false,
    protected: bool = false,
    mutable_format: bool = false,
    deferred_memory_allocation: bool = false,

    _: u28 = 0,

    pub const Bits = enum(c_uint) {
        split_instance_bind_regions = 0x00000001,
        protected = 0x00000002,
        mutable_format = 0x00000004,
        deferred_memory_allocation = 0x00000008,
    };
};

pub const VkSwapchainCreateInfoKHR = struct {
    pNext: ?*const anyopaque = null,
    flags: VkSwapchainCreateFlagsKHR = .{},
    surface: l0vk.VkSurfaceKHR,
    minImageCount: u32,
    imageFormat: l0vk.VkFormat,
    imageColorSpace: l0vk.VkColorSpaceKHR,
    imageExtent: VkExtent2D,
    imageArrayLayers: u32,
    imageUsage: l0vk.VkImageUsageFlags,
    imageSharingMode: VkSharingMode,
    queueFamilyIndices: []const u32,
    preTransform: l0vk.VkSurfaceTransformFlagsKHR.Bits,
    compositeAlpha: l0vk.VkCompositeAlphaFlagsKHR.Bits,
    presentMode: l0vk.VkPresentModeKHR,
    clipped: bool,
    oldSwapchain: VkSwapchainKHR = @ptrCast(vulkan.VK_NULL_HANDLE),

    pub fn to_vulkan_ty(self: *const VkSwapchainCreateInfoKHR) vulkan.VkSwapchainCreateInfoKHR {
        var clipped = vulkan.VK_FALSE;
        if (self.clipped) {
            clipped = vulkan.VK_TRUE;
        }

        return vulkan.VkSwapchainCreateInfoKHR{
            .sType = vulkan.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .pNext = self.pNext,
            .flags = @bitCast(self.flags),
            .surface = self.surface,
            .minImageCount = self.minImageCount,
            .imageFormat = @intFromEnum(self.imageFormat),
            .imageColorSpace = @intFromEnum(self.imageColorSpace),
            .imageExtent = self.imageExtent,
            .imageArrayLayers = self.imageArrayLayers,
            .imageUsage = @bitCast(self.imageUsage),
            .imageSharingMode = @intFromEnum(self.imageSharingMode),
            .queueFamilyIndexCount = @intCast(self.queueFamilyIndices.len),
            .pQueueFamilyIndices = self.queueFamilyIndices.ptr,
            .preTransform = @intFromEnum(self.preTransform),
            .compositeAlpha = @intFromEnum(self.compositeAlpha),
            .presentMode = @intFromEnum(self.presentMode),
            .clipped = clipped,
            .oldSwapchain = self.oldSwapchain,
        };
    }
};

pub const vkCreateSwapchainKHRError = error{
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
    VK_ERROR_DEVICE_LOST,
    VK_ERROR_SURFACE_LOST_KHR,
    VK_ERROR_NATIVE_WINDOW_IN_USE_KHR,
    VK_ERROR_INITIALIZATION_FAILED,
    VK_ERROR_COMPRESSION_EXHAUSTED_EXT,
};

pub fn vkCreateSwapchainKHR(
    device: l0vk.VkDevice,
    pCreateInfo: *const VkSwapchainCreateInfoKHR,
    pAllocator: [*c]const l0vk.VkAllocationCallbacks,
) !VkSwapchainKHR {
    var swapchain: vulkan.VkSwapchainKHR = undefined;
    const create_info = pCreateInfo.to_vulkan_ty();
    var result = vulkan.vkCreateSwapchainKHR(device, &create_info, pAllocator, &swapchain);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkCreateSwapchainKHRError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkCreateSwapchainKHRError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_DEVICE_LOST => return vkCreateSwapchainKHRError.VK_ERROR_DEVICE_LOST,
            vulkan.VK_ERROR_SURFACE_LOST_KHR => return vkCreateSwapchainKHRError.VK_ERROR_SURFACE_LOST_KHR,
            vulkan.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => return vkCreateSwapchainKHRError.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR,
            vulkan.VK_ERROR_INITIALIZATION_FAILED => return vkCreateSwapchainKHRError.VK_ERROR_INITIALIZATION_FAILED,
            vulkan.VK_ERROR_COMPRESSION_EXHAUSTED_EXT => return vkCreateSwapchainKHRError.VK_ERROR_COMPRESSION_EXHAUSTED_EXT,
            else => unreachable,
        }
    }

    return swapchain;
}

pub const vkGetSwapchainImagesKHRError = error{
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
    VK_INCOMPLETE,

    OutOfMemory,
};

pub fn vkGetSwapchainImagesKHR(
    allocator: std.mem.Allocator,
    device: l0vk.VkDevice,
    swapchain: l0vk.VkSwapchainKHR,
) vkGetSwapchainImagesKHRError![]l0vk.VkImage {
    var image_count: u32 = undefined;
    var result = vulkan.vkGetSwapchainImagesKHR(device, swapchain, &image_count, null);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkGetSwapchainImagesKHRError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkGetSwapchainImagesKHRError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_INCOMPLETE => return vkGetSwapchainImagesKHRError.VK_INCOMPLETE,
            else => unreachable,
        }
    }

    var images = try allocator.alloc(l0vk.VkImage, image_count);
    result = vulkan.vkGetSwapchainImagesKHR(device, swapchain, &image_count, images.ptr);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkGetSwapchainImagesKHRError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkGetSwapchainImagesKHRError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_INCOMPLETE => return vkGetSwapchainImagesKHRError.VK_INCOMPLETE,
            else => unreachable,
        }
    }

    return images;
}
