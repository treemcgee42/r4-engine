const std = @import("std");
const vulkan = @import("vulkan");
const Window = @import("../../Window.zig");
const cimgui = @import("cimgui");
const VulkanError = @import("./VulkanSystem.zig").VulkanError;
const Swapchain = @import("./Swapchain.zig");
const VulkanSystem = @import("./VulkanSystem.zig");
const RenderPassInfo = @import("../RenderPass.zig").RenderPassInfo;
const buffer = @import("buffer.zig");

const RenderPass = @This();

render_pass: vulkan.VkRenderPass,

images: []Image,
framebuffers: []vulkan.VkFramebuffer,
render_area: RenderArea,

imgui_enabled: bool,
imgui_descriptor_pool: vulkan.VkDescriptorPool = null,

const Image = union(enum) {
    color: buffer.ColorImage,
};

pub const RenderArea = struct {
    width: u32,
    height: u32,
};

pub const RenderPassInitInfo = struct {
    system: *VulkanSystem,
    window: *Window,

    imgui_enabled: bool,
    tag: enum {
        basic_primary,
    },
    render_area: RenderArea,
};

pub fn init(info: *const RenderPassInitInfo) VulkanError!RenderPass {
    var system = info.system;
    var swapchain = &info.window.swapchain.swapchain;

    var render_pass: vulkan.VkRenderPass = undefined;
    switch (info.tag) {
        .basic_primary => {
            var clear = true;
            if (info.imgui_enabled) {
                clear = false;
            }
            render_pass = try build_basic_primary_renderpass(system, swapchain, clear);
        },
    }

    var images: []Image = undefined;
    switch (info.tag) {
        .basic_primary => {
            images = try system.allocator.alloc(Image, 0);
        },
    }

    var framebuffers: []vulkan.VkFramebuffer = undefined;
    switch (info.tag) {
        .basic_primary => {
            framebuffers = try create_basic_primary_framebuffers(system, swapchain, render_pass);
        },
    }

    var to_return = RenderPass{
        .render_pass = render_pass,

        .images = images,
        .framebuffers = framebuffers,
        .render_area = info.render_area,

        // Potentially updated before returning.
        .imgui_enabled = false,
    };

    if (info.imgui_enabled) {
        try to_return.setup_imgui(system, info.window);
        std.log.info("imgui initialized", .{});
    }

    return to_return;
}

pub fn deinit(self: *RenderPass, allocator: std.mem.Allocator, system: *VulkanSystem) void {
    if (self.imgui_enabled) {
        vulkan.vkDestroyDescriptorPool(system.logical_device, self.imgui_descriptor_pool, null);
        cimgui.ImGui_ImplVulkan_Shutdown();
        cimgui.ImGui_ImplGlfw_Shutdown();
        cimgui.igDestroyContext(null);
    }

    var i: usize = 0;
    while (i < self.framebuffers.len) : (i += 1) {
        vulkan.vkDestroyFramebuffer(system.logical_device, self.framebuffers[i], null);
    }
    allocator.free(self.framebuffers);

    i = 0;
    while (i < self.images.len) : (i += 1) {
        self.images[i].color.deinit(system.logical_device);
    }
    allocator.free(self.images);

    vulkan.vkDestroyRenderPass(system.logical_device, self.render_pass, null);
}

pub fn setup_imgui(self: *RenderPass, system: *VulkanSystem, window: *Window) VulkanError!void {
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
    var result = vulkan.vkCreateDescriptorPool(system.logical_device, &pool_info, null, &imgui_pool);
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
        .Instance = @ptrCast(system.instance),
        .PhysicalDevice = @ptrCast(system.physical_device),
        .Device = @ptrCast(system.logical_device),
        .Queue = @ptrCast(system.graphics_queue),
        .DescriptorPool = @ptrCast(self.imgui_descriptor_pool),
        .MinImageCount = @intCast(window.swapchain.swapchain.swapchain_images.len),
        .ImageCount = @intCast(window.swapchain.swapchain.swapchain_images.len),
        .MSAASamples = vulkan.VK_SAMPLE_COUNT_1_BIT,
    };
    _ = cimgui.ImGui_ImplVulkan_Init(@ptrCast(&vulkan_init_info), @ptrCast(self.render_pass));

    // --- Load fonts.

    var command_pool = system.command_pool;
    var command_buffer = window.swapchain.swapchain.a_command_buffers[0];

    result = vulkan.vkResetCommandPool(system.logical_device, command_pool, 0);
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
    result = vulkan.vkQueueSubmit(system.graphics_queue, 1, &end_info, null);
    if (result != vulkan.VK_SUCCESS) {
        return VulkanError.vk_error_out_of_host_memory;
    }
    result = vulkan.vkDeviceWaitIdle(system.logical_device);
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
}

pub fn begin(
    self: *RenderPass,
    command_buffer: vulkan.VkCommandBuffer,
    image_index: u32,
    clear: bool,
) void {
    var clearValueCount: u32 = 0;
    var clear_values = [_]vulkan.VkClearValue{
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
    var pClearValues: ?*vulkan.VkClearValue = @ptrCast(clear_values[0..].ptr);
    if (clear) {
        clearValueCount = clear_values.len;
    }

    var framebuffer = self.framebuffers[0];
    if (self.framebuffers.len > 1) {
        framebuffer = self.framebuffers[image_index];
    }

    const render_pass_info = vulkan.VkRenderPassBeginInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = self.render_pass,
        .framebuffer = framebuffer,
        .renderArea = vulkan.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = self.render_area.width, .height = self.render_area.height },
        },
        .clearValueCount = clearValueCount,
        .pClearValues = pClearValues,

        .pNext = null,
    };

    vulkan.vkCmdBeginRenderPass(command_buffer, &render_pass_info, vulkan.VK_SUBPASS_CONTENTS_INLINE);
}

pub fn end(self: *RenderPass, command_buffer: vulkan.VkCommandBuffer) void {
    if (self.imgui_enabled) {
        cimgui.ImGui_ImplVulkan_RenderDrawData(cimgui.igGetDrawData(), @ptrCast(command_buffer), null);
    }

    vulkan.vkCmdEndRenderPass(command_buffer);
}

pub fn resize_callback(
    self: *RenderPass,
    allocator: std.mem.Allocator,
    system: *VulkanSystem,
    swapchain: *Swapchain,
    new_render_area: RenderArea,
) VulkanError!void {
    var i: usize = 0;
    while (i < self.framebuffers.len) : (i += 1) {
        vulkan.vkDestroyFramebuffer(system.logical_device, self.framebuffers[i], null);
    }
    allocator.free(self.framebuffers);

    self.framebuffers = try create_basic_primary_framebuffers(system, swapchain, self.render_pass);
    self.render_area = new_render_area;
}

// --- Vulkan renderpass. {{{1

const AttachmentAndRef = struct {
    attachment: vulkan.VkAttachmentDescription,
    ref: vulkan.VkAttachmentReference,
};

fn build_color_attachment(swapchain: *Swapchain, clear: bool) VulkanError!AttachmentAndRef {
    var loadOp = vulkan.VK_ATTACHMENT_LOAD_OP_CLEAR;
    if (!clear) {
        loadOp = vulkan.VK_ATTACHMENT_LOAD_OP_LOAD;
    }
    var initialLayout = vulkan.VK_IMAGE_LAYOUT_UNDEFINED;
    if (!clear) {
        initialLayout = vulkan.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    }
    var finalLayout = vulkan.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    if (!clear) {
        finalLayout = vulkan.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    }

    const color_attachment = vulkan.VkAttachmentDescription{
        .format = @intFromEnum(swapchain.swapchain_image_format),
        // The top-level render pass doesn't need multisampling.
        .samples = 1,
        .loadOp = @intCast(loadOp),
        .storeOp = vulkan.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = vulkan.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = vulkan.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = @intCast(initialLayout),
        .finalLayout = @intCast(finalLayout),
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

fn build_basic_primary_renderpass(system: *VulkanSystem, swapchain: *Swapchain, clear: bool) VulkanError!vulkan.VkRenderPass {
    // --- Attachments.

    const color_attachment_count = 1;
    var color_attachment = try build_color_attachment(swapchain, clear);
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
    const result = vulkan.vkCreateRenderPass(system.logical_device, &render_pass_info, null, &render_pass);
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
    system: *VulkanSystem,
    swapchain: *Swapchain,
    render_pass: vulkan.VkRenderPass,
) VulkanError![]vulkan.VkFramebuffer {
    const allocator = system.allocator;
    var framebuffers = try allocator.alloc(vulkan.VkFramebuffer, swapchain.swapchain_image_views.len);
    errdefer allocator.free(framebuffers);

    var i: usize = 0;
    while (i < swapchain.swapchain_image_views.len) : (i += 1) {
        const attachments = [_]vulkan.VkImageView{
            swapchain.swapchain_image_views[i],
        };

        var framebuffer_info = vulkan.VkFramebufferCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = render_pass,
            .attachmentCount = attachments.len,
            .pAttachments = attachments[0..].ptr,
            .width = swapchain.swapchain_extent.width,
            .height = swapchain.swapchain_extent.height,
            .layers = 1,

            .pNext = null,
            .flags = 0,
        };

        const result = vulkan.vkCreateFramebuffer(system.logical_device, &framebuffer_info, null, &framebuffers[i]);
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

fn create_basic_deferred_framebuffers(
    allocator: std.mem.Allocator,
    system: *VulkanSystem,
    width: u32,
    height: u32,
    image_view: vulkan.VkImageView,
    render_pass: vulkan.VkRenderPass,
) VulkanError![]vulkan.VkFramebuffer {
    var framebuffers = try allocator.alloc(vulkan.VkFramebuffer, 1);
    errdefer allocator.free(framebuffers);

    const attachments = [_]vulkan.VkImageView{
        image_view,
    };

    var framebuffer_info = vulkan.VkFramebufferCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
        .renderPass = render_pass,
        .attachmentCount = attachments.len,
        .pAttachments = attachments[0..].ptr,
        .width = width,
        .height = height,
        .layers = 1,

        .pNext = null,
        .flags = 0,
    };

    const result = vulkan.vkCreateFramebuffer(system.logical_device, &framebuffer_info, null, &framebuffers[0]);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            else => unreachable,
        }
    }

    return framebuffers;
}

// --- }}}1
