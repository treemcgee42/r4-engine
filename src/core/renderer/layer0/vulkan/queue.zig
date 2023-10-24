const vulkan = @import("vulkan");
const l0vk = @import("./vulkan.zig");

pub const VkQueueFlags = packed struct(u32) {
    graphics: bool = false,
    compute: bool = false,
    transfer: bool = false,
    sparse_binding: bool = false,

    // Provided by VK_VERSION_1_1
    protected: bool = false,
    // Provided by VK_KHR_video_decode_queue
    video_decode: bool = false,
    _: u2 = 0,

    // Provided by VK_NV_optical_flow
    optical_flow: bool = false,
    _a: u3 = 0,

    _b: u20 = 0,

    pub fn to_vulkan_ty(self: VkQueueFlags) vulkan.VkQueueFlags {
        return @bitCast(self);
    }
};

pub const VkQueueFamilyProperties = struct {
    queueFlags: VkQueueFlags = .{},
    queueCount: u32 = 0,
    timestampValidBits: u32 = 0,
    minImageTransferGranularity: l0vk.VkExtent3D = .{ .width = 0, .height = 0, .depth = 0 },

    pub fn to_vulkan_ty(self: VkQueueFamilyProperties) vulkan.VkQueueFamilyProperties {
        return .{
            .queueFlags = self.queueFlags.to_vulkan_ty(),
            .queueCount = self.queueCount,
            .timestampValidBits = self.timestampValidBits,
            .minImageTransferGranularity = self.minImageTransferGranularity,
        };
    }

    pub fn from_vulkan_ty(queue_family_properties: vulkan.VkQueueFamilyProperties) VkQueueFamilyProperties {
        return .{
            .queueFlags = @bitCast(queue_family_properties.queueFlags),
            .queueCount = queue_family_properties.queueCount,
            .timestampValidBits = queue_family_properties.timestampValidBits,
            .minImageTransferGranularity = queue_family_properties.minImageTransferGranularity,
        };
    }
};

pub const VkSubmitInfo = struct {
    pNext: ?*const anyopaque = null,
    waitSemaphores: []l0vk.VkSemaphore,
    pWaitDstStageMask: *const l0vk.VkPipelineStageFlags,
    commandBuffers: []l0vk.VkCommandBuffer,
    signalSemaphores: []l0vk.VkSemaphore,

    pub fn to_vulkan_ty(self: *const VkSubmitInfo) vulkan.VkSubmitInfo {
        const mask: vulkan.VkPipelineStageFlags = @bitCast(self.pWaitDstStageMask.*);

        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .pNext = self.pNext,
            .waitSemaphoreCount = @intCast(self.waitSemaphores.len),
            .pWaitSemaphores = self.waitSemaphores.ptr,
            .pWaitDstStageMask = &mask,
            .commandBufferCount = @intCast(self.commandBuffers.len),
            .pCommandBuffers = self.commandBuffers.ptr,
            .signalSemaphoreCount = @intCast(self.signalSemaphores.len),
            .pSignalSemaphores = self.signalSemaphores.ptr,
        };
    }
};

pub const vkQueueSubmitError = error{
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
    VK_ERROR_DEVICE_LOST,
};

pub const VkQueue = vulkan.VkQueue;

pub fn vkQueueSubmit(
    queue: VkQueue,
    submitCount: u32,
    pSubmits: *const VkSubmitInfo,
    fence: l0vk.VkFence,
) vkQueueSubmitError!void {
    const submits = pSubmits.to_vulkan_ty();

    var result = vulkan.vkQueueSubmit(
        queue,
        submitCount,
        &submits,
        fence,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkQueueSubmitError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkQueueSubmitError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_DEVICE_LOST => return vkQueueSubmitError.VK_ERROR_DEVICE_LOST,
            else => unreachable,
        }
    }
}

pub fn vkGetDeviceQueue(
    device: l0vk.VkDevice,
    queueFamilyIndex: u32,
    queueIndex: u32,
) VkQueue {
    var queue: VkQueue = undefined;
    vulkan.vkGetDeviceQueue(device, queueFamilyIndex, queueIndex, &queue);
    return queue;
}
