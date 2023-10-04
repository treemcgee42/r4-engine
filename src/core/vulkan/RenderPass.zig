const std = @import("std");
const vulkan = @import("../../c/vulkan.zig");
const VulkanError = @import("./VulkanSystem.zig").VulkanError;
const Core = @import("../Core.zig");
const Swapchain = @import("./Swapchain.zig");
const Window = @import("../Window.zig");
const PipelineSystem = @import("./PipelineSystem.zig");

const RenderPass = @This();

render_pass: vulkan.VkRenderPass,
framebuffers: []vulkan.VkFramebuffer,
pipeline: vulkan.VkPipeline,

pub const RenderPassInitInfo = struct {
    tag: Tag,
    p_window: *Window,

    pub const Tag = enum {
        basic_primary,
    };
};

pub fn init_basic_primary(core: *Core, info: RenderPassInitInfo) VulkanError!RenderPass {
    const render_pass = try build_basic_primary_renderpass(core, info.p_window);
    const framebuffers = try create_basic_primary_framebuffers(core, info.p_window, render_pass);
    const pipeline = try core.vulkan_system.pipeline_system.get_or_build_pipeline(core, PipelineSystem.PipelineInitInfo.init_swapchain(), render_pass);

    return .{
        .render_pass = render_pass,
        .framebuffers = framebuffers,
        .pipeline = pipeline,
    };
}

pub fn deinit(self: *RenderPass, core: *Core) void {
    var i: usize = 0;
    while (i < self.framebuffers.len) : (i += 1) {
        vulkan.vkDestroyFramebuffer(core.vulkan_system.logical_device, self.framebuffers[i], null);
    }
    core.allocator.free(self.framebuffers);

    vulkan.vkDestroyRenderPass(core.vulkan_system.logical_device, self.render_pass, null);
}

pub fn record_commands(self: *RenderPass, window: *Window, command_buffer: vulkan.VkCommandBuffer, image_index: u32) void {
    // --- Begin render pass.

    const clear_values = [_]vulkan.VkClearValue{
        .{
            .color = .{
                .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 },
            },
        },
        .{
            .depthStencil = .{
                .depth = 1.0,
                .stencil = 0,
            },
        },
    };

    const render_pass_info = vulkan.VkRenderPassBeginInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = self.render_pass,
        .framebuffer = self.framebuffers[image_index],
        .renderArea = vulkan.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = window.swapchain.swapchain_extent,
        },
        .clearValueCount = clear_values.len,
        .pClearValues = clear_values[0..].ptr,

        .pNext = null,
    };

    vulkan.vkCmdBeginRenderPass(command_buffer, &render_pass_info, vulkan.VK_SUBPASS_CONTENTS_INLINE);

    // --- Draw.

    vulkan.vkCmdBindPipeline(command_buffer, vulkan.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline);

    const viewport = vulkan.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(window.swapchain.swapchain_extent.width),
        .height = @floatFromInt(window.swapchain.swapchain_extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    vulkan.vkCmdSetViewport(command_buffer, 0, 1, &viewport);

    const scissor = vulkan.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = window.swapchain.swapchain_extent,
    };
    vulkan.vkCmdSetScissor(command_buffer, 0, 1, &scissor);

    vulkan.vkCmdDraw(command_buffer, 3, 1, 0, 0);

    // --- End render pass.

    vulkan.vkCmdEndRenderPass(command_buffer);
}

pub fn recreate_swapchain_callback(self: *RenderPass, window: *Window, core: *Core) VulkanError!void {
    var i: usize = 0;
    while (i < self.framebuffers.len) : (i += 1) {
        vulkan.vkDestroyFramebuffer(core.vulkan_system.logical_device, self.framebuffers[i], null);
    }
    core.allocator.free(self.framebuffers);

    self.framebuffers = try create_basic_primary_framebuffers(core, window, self.render_pass);
}

// --- Vulkan renderpass. {{{1

const AttachmentAndRef = struct {
    attachment: vulkan.VkAttachmentDescription,
    ref: vulkan.VkAttachmentReference,
};

fn build_color_attachment(window: *Window) VulkanError!AttachmentAndRef {
    const color_attachment = vulkan.VkAttachmentDescription{
        .format = window.swapchain.swapchain_image_format,
        // The top-level render pass doesn't need multisampling.
        .samples = 1,
        .loadOp = vulkan.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = vulkan.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = vulkan.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = vulkan.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = vulkan.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = vulkan.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };

    const color_attachment_ref = vulkan.VkAttachmentReference{
        .attachment = 0,
        .layout = vulkan.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    return AttachmentAndRef{
        .attachment = color_attachment,
        .ref = color_attachment_ref,
    };
}

fn build_basic_primary_renderpass(core: *Core, window: *Window) VulkanError!vulkan.VkRenderPass {
    // --- Attachments.

    const color_attachment_count = 1;
    var color_attachment = try build_color_attachment(window);
    var pColorAttachments: [*c]vulkan.VkAttachmentReference = &color_attachment.ref;

    // --- Subpass.

    const subpass = vulkan.VkSubpassDescription{
        .pipelineBindPoint = vulkan.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = color_attachment_count,
        .pColorAttachments = pColorAttachments,
        .pDepthStencilAttachment = null,
        .pResolveAttachments = null,

        .flags = 0,
        .inputAttachmentCount = 0,
        .pInputAttachments = null,
        .preserveAttachmentCount = 0,
        .pPreserveAttachments = null,
    };

    // ---

    const attachments = [_]vulkan.VkAttachmentDescription{color_attachment.attachment};

    const render_pass_info = vulkan.VkRenderPassCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = attachments.len,
        .pAttachments = attachments[0..].ptr,
        .subpassCount = 1,
        .pSubpasses = &subpass,

        .dependencyCount = 0,
        .pDependencies = null,
        .flags = 0,
        .pNext = null,
    };

    var render_pass: vulkan.VkRenderPass = undefined;
    const result = vulkan.vkCreateRenderPass(core.vulkan_system.logical_device, &render_pass_info, null, &render_pass);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            else => unreachable,
        }
    }

    return render_pass;
}

// --- }}}1

// --- Framebuffers. {{{1

fn create_basic_primary_framebuffers(
    core: *Core,
    window: *Window,
    render_pass: vulkan.VkRenderPass,
) VulkanError![]vulkan.VkFramebuffer {
    var framebuffers = try core.allocator.alloc(vulkan.VkFramebuffer, window.swapchain.swapchain_image_views.len);
    errdefer core.allocator.free(framebuffers);

    var i: usize = 0;
    while (i < window.swapchain.swapchain_image_views.len) : (i += 1) {
        const attachments = [_]vulkan.VkImageView{
            window.swapchain.swapchain_image_views[i],
        };

        var framebuffer_info = vulkan.VkFramebufferCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = render_pass,
            .attachmentCount = attachments.len,
            .pAttachments = attachments[0..].ptr,
            .width = window.swapchain.swapchain_extent.width,
            .height = window.swapchain.swapchain_extent.height,
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

// --- }}}1
