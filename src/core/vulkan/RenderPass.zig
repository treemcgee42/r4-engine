const std = @import("std");
const vulkan = @import("../../c/vulkan.zig");
const cimgui = @import("../../c/cimgui.zig");
const VulkanError = @import("./VulkanSystem.zig").VulkanError;
const Core = @import("../Core.zig");
const Swapchain = @import("./Swapchain.zig");
const Window = @import("../Window.zig");
const PipelineSystem = @import("./PipelineSystem.zig");

const RenderPass = @This();

render_pass: vulkan.VkRenderPass,
framebuffers: []vulkan.VkFramebuffer,
pipeline: vulkan.VkPipeline,

imgui_enabled: bool,
imgui_descriptor_pool: vulkan.VkDescriptorPool = null,

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

        .imgui_enabled = false,
    };
}

pub fn deinit(self: *RenderPass, core: *Core) void {
    if (self.imgui_enabled) {
        vulkan.vkDestroyDescriptorPool(core.vulkan_system.logical_device, self.imgui_descriptor_pool, null);
        cimgui.ImGui_ImplVulkan_Shutdown();
        cimgui.ImGui_ImplGlfw_Shutdown();
        cimgui.igDestroyContext(null);
    }

    var i: usize = 0;
    while (i < self.framebuffers.len) : (i += 1) {
        vulkan.vkDestroyFramebuffer(core.vulkan_system.logical_device, self.framebuffers[i], null);
    }
    core.allocator.free(self.framebuffers);

    vulkan.vkDestroyRenderPass(core.vulkan_system.logical_device, self.render_pass, null);
}

pub fn setup_imgui(self: *RenderPass, core: *Core, window: *Window) VulkanError!void {
    self.imgui_enabled = true;

    // --- Descriptor pool.

    const pool_sizes = [_]vulkan.VkDescriptorPoolSize{
        .{
            .type = vulkan.VK_DESCRIPTOR_TYPE_SAMPLER,
            .descriptorCount = 1000,
        },
        .{
            .type = vulkan.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1000,
        },
        .{
            .type = vulkan.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
            .descriptorCount = 1000,
        },
        .{
            .type = vulkan.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .descriptorCount = 1000,
        },
        .{
            .type = vulkan.VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER,
            .descriptorCount = 1000,
        },
        .{
            .type = vulkan.VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER,
            .descriptorCount = 1000,
        },
        .{
            .type = vulkan.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 1000,
        },
        .{
            .type = vulkan.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 1000,
        },
        .{
            .type = vulkan.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
            .descriptorCount = 1000,
        },
        .{
            .type = vulkan.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC,
            .descriptorCount = 1000,
        },
        .{
            .type = vulkan.VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT,
            .descriptorCount = 1000,
        },
    };

    const pool_info = vulkan.VkDescriptorPoolCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .flags = vulkan.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
        .maxSets = 1000,
        .poolSizeCount = @intCast(pool_sizes.len),
        .pPoolSizes = pool_sizes[0..].ptr,
    };

    var imgui_pool: vulkan.VkDescriptorPool = undefined;
    var result = vulkan.vkCreateDescriptorPool(core.vulkan_system.logical_device, &pool_info, null, &imgui_pool);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            else => unreachable,
        }
    }
    self.imgui_descriptor_pool = imgui_pool;

    // --- Initialize imgui library.

    _ = cimgui.igCreateContext(null);
    _ = cimgui.ImGui_ImplGlfw_InitForVulkan(@ptrCast(window.window), true);

    var vulkan_init_info = cimgui.ImGui_ImplVulkan_InitInfo{
        .Instance = @ptrCast(core.vulkan_system.instance),
        .PhysicalDevice = @ptrCast(core.vulkan_system.physical_device),
        .Device = @ptrCast(core.vulkan_system.logical_device),
        .Queue = @ptrCast(core.vulkan_system.graphics_queue),
        .DescriptorPool = @ptrCast(self.imgui_descriptor_pool),
        .MinImageCount = @intCast(window.swapchain.swapchain_images.len),
        .ImageCount = @intCast(window.swapchain.swapchain_images.len),
        .MSAASamples = vulkan.VK_SAMPLE_COUNT_1_BIT,
    };
    _ = cimgui.ImGui_ImplVulkan_Init(@ptrCast(&vulkan_init_info), @ptrCast(self.render_pass));

    // --- Load fonts.

    var command_pool = core.vulkan_system.command_pool;
    var command_buffer = core.vulkan_system.command_buffers[0];

    result = vulkan.vkResetCommandPool(core.vulkan_system.logical_device, command_pool, 0);
    if (result != vulkan.VK_SUCCESS) {
        return VulkanError.vk_error_out_of_host_memory;
    }
    const cb_begin_info = vulkan.VkCommandBufferBeginInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = vulkan.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,

        .pNext = null,
        .pInheritanceInfo = null,
    };
    result = vulkan.vkBeginCommandBuffer(command_buffer, &cb_begin_info);
    if (result != vulkan.VK_SUCCESS) {
        return VulkanError.vk_error_out_of_host_memory;
    }

    _ = cimgui.ImGui_ImplVulkan_CreateFontsTexture(@ptrCast(command_buffer));

    const end_info = vulkan.VkSubmitInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &command_buffer,

        .pNext = null,
        .waitSemaphoreCount = 0,
        .pWaitSemaphores = null,
        .signalSemaphoreCount = 0,
        .pSignalSemaphores = null,
        .pWaitDstStageMask = null,
    };
    result = vulkan.vkEndCommandBuffer(command_buffer);
    if (result != vulkan.VK_SUCCESS) {
        return VulkanError.vk_error_out_of_host_memory;
    }
    result = vulkan.vkQueueSubmit(core.vulkan_system.graphics_queue, 1, &end_info, null);
    if (result != vulkan.VK_SUCCESS) {
        return VulkanError.vk_error_out_of_host_memory;
    }
    result = vulkan.vkDeviceWaitIdle(core.vulkan_system.logical_device);
    if (result != vulkan.VK_SUCCESS) {
        return VulkanError.vk_error_out_of_host_memory;
    }

    _ = cimgui.ImGui_ImplVulkan_DestroyFontUploadObjects();

    // //execute a gpu command to upload imgui font textures
    // immediate_submit([&](VkCommandBuffer cmd) {
    // 	ImGui_ImplVulkan_CreateFontsTexture(cmd);
    // 	});
    //
    // //clear font textures from cpu data
    // ImGui_ImplVulkan_DestroyFontUploadObjects();
    //

    std.log.info("imgui initialized", .{});
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

    if (self.imgui_enabled) {
        cimgui.ImGui_ImplVulkan_RenderDrawData(cimgui.igGetDrawData(), @ptrCast(command_buffer), null);
    }

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
