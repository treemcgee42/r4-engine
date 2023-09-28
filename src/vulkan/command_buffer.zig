const vulkan = @import("../c.zig").vulkan;
const VulkanError = @import("./vulkan.zig").VulkanError;

pub fn begin_single_time_commands(device: vulkan.VkDevice, command_pool: vulkan.VkCommandPool) VulkanError!vulkan.VkCommandBuffer {
    const alloc_info = vulkan.VkCommandBufferAllocateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = vulkan.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };

    var command_buffer: vulkan.VkCommandBuffer = undefined;
    var result = vulkan.vkAllocateCommandBuffers(device, &alloc_info, &command_buffer);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            else => unreachable,
        }
    }
    errdefer vulkan.vkFreeCommandBuffers(device, command_pool, 1, &command_buffer);

    const command_buffer_begin_info = vulkan.VkCommandBufferBeginInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = vulkan.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,

        .pInheritanceInfo = null,
        .pNext = null,
    };

    result = vulkan.vkBeginCommandBuffer(command_buffer, &command_buffer_begin_info);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            else => unreachable,
        }
    }

    return command_buffer;
}

pub fn end_single_time_commands(
    device: vulkan.VkDevice,
    command_pool: vulkan.VkCommandPool,
    graphics_queue: vulkan.VkQueue,
    command_buffer: vulkan.VkCommandBuffer,
) VulkanError!void {
    var result = vulkan.vkEndCommandBuffer(command_buffer);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return,
            else => unreachable,
        }
    }

    const submit_info = vulkan.VkSubmitInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &command_buffer,

        .pNext = null,
        .waitSemaphoreCount = 0,
        .pWaitSemaphores = null,
        .pWaitDstStageMask = null,
        .signalSemaphoreCount = 0,
        .pSignalSemaphores = null,
    };

    result = vulkan.vkQueueSubmit(graphics_queue, 1, &submit_info, null);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            else => unreachable,
        }
    }

    result = vulkan.vkQueueWaitIdle(graphics_queue);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            else => unreachable,
        }
    }

    vulkan.vkFreeCommandBuffers(device, command_pool, 1, &command_buffer);
}
