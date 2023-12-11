const std = @import("std");
const vulkan = @import("vulkan");
const l0vk = @import("./vulkan.zig");

pub const VkSemaphore = vulkan.VkSemaphore;

pub const VkSemaphoreCreateFlags = packed struct(u32) {
    _: u32 = 0,
};

pub const VkSemaphoreCreateInfo = extern struct {
    pNext: ?*const anyopaque = null,
    flags: VkSemaphoreCreateFlags = .{},

    pub fn to_vulkan_ty(self: *const VkSemaphoreCreateInfo) vulkan.VkSemaphoreCreateInfo {
        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
            .pNext = self.pNext,
            .flags = @bitCast(self.flags),
        };
    }
};

pub const vkCreateSemaphoreError = error{
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
};

pub fn vkCreateSemaphore(
    device: l0vk.VkDevice,
    pCreateInfo: *const VkSemaphoreCreateInfo,
    pAllocator: ?*const l0vk.VkAllocationCallbacks,
) vkCreateSemaphoreError!VkSemaphore {
    var create_info = pCreateInfo.to_vulkan_ty();

    var semaphore: vulkan.VkSemaphore = undefined;
    const result = vulkan.vkCreateSemaphore(
        device,
        &create_info,
        pAllocator,
        &semaphore,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkCreateSemaphoreError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkCreateSemaphoreError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            else => unreachable,
        }
    }

    return semaphore;
}

pub inline fn vkDestroySemaphore(
    device: l0vk.VkDevice,
    semaphore: VkSemaphore,
    pAllocator: ?*const l0vk.VkAllocationCallbacks,
) void {
    vulkan.vkDestroySemaphore(device, semaphore, pAllocator);
}

pub const VkFence = vulkan.VkFence;

pub const VkFenceCreateFlags = packed struct(u32) {
    signaled: bool = false,
    _: u3 = 0,

    _a: u28 = 0,

    pub const Bits = enum(c_uint) {
        signaled = 0x00000001,
    };
};

pub const VkFenceCreateInfo = struct {
    pNext: ?*const anyopaque = null,
    flags: VkFenceCreateFlags = .{},

    pub fn to_vulkan_ty(self: *const VkFenceCreateInfo) vulkan.VkFenceCreateInfo {
        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .pNext = self.pNext,
            .flags = @bitCast(self.flags),
        };
    }
};

pub const vkCreateFenceError = error{
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
};

pub fn vkCreateFence(
    device: l0vk.VkDevice,
    pCreateInfo: *const VkFenceCreateInfo,
    pAllocator: ?*const l0vk.VkAllocationCallbacks,
) vkCreateFenceError!VkFence {
    var create_info = pCreateInfo.to_vulkan_ty();

    var fence: vulkan.VkFence = undefined;
    const result = vulkan.vkCreateFence(
        device,
        &create_info,
        pAllocator,
        &fence,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkCreateFenceError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkCreateFenceError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            else => unreachable,
        }
    }

    return fence;
}

pub inline fn vkDestroyFence(
    device: l0vk.VkDevice,
    fence: VkFence,
    pAllocator: ?*const l0vk.VkAllocationCallbacks,
) void {
    vulkan.vkDestroyFence(device, fence, pAllocator);
}
