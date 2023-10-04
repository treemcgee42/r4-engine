const std = @import("std");
const vulkan = @import("../../c/vulkan.zig");
const buffer = @import("./buffer.zig");
const VulkanError = @import("./VulkanSystem.zig").VulkanError;
const Core = @import("../Core.zig");

pub fn create_swapchain_framebuffers(
    core: *Core,
    swapchain_image_views: []vulkan.VkImageView,
    swapchain_extent: vulkan.VkExtent2D,
) VulkanError![]vulkan.VkFramebuffer {
    const allocator_ = core.gpa.allocator();
    var framebuffers = try allocator_.alloc(vulkan.VkFramebuffer, swapchain_image_views.len);
    errdefer allocator_.free(framebuffers);

    var i: usize = 0;
    while (i < swapchain_image_views.len) : (i += 1) {
        const attachments = [_]vulkan.VkImageView{
            swapchain_image_views[i],
        };

        var framebuffer_info = vulkan.VkFramebufferCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = null,
            .attachmentCount = attachments.len,
            .pAttachments = attachments[0..].ptr,
            .width = swapchain_extent.width,
            .height = swapchain_extent.height,
            .layers = 1,

            .pNext = null,
            .flags = 0,
        };

        const result = vulkan.vkCreateFramebuffer(core.vulkan_system.logical_device, &framebuffer_info, null, &framebuffers[i]);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }
    }

    return framebuffers;
}
