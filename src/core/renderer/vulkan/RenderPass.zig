const std = @import("std");
const l0vk = @import("../layer0/vulkan/vulkan.zig");
const Window = @import("../../Window.zig");
const cimgui = @import("cimgui");
const Swapchain = @import("./Swapchain.zig");
const VulkanSystem = @import("./VulkanSystem.zig");
const RenderPassInfo = @import("../RenderPass.zig").RenderPassInfo;
const buffer = @import("buffer.zig");

const RenderPass = @This();

render_pass: l0vk.VkRenderPass,

images: []Image,
framebuffers: []l0vk.VkFramebuffer,
render_area: RenderArea,

imgui_enabled: bool,
imgui_descriptor_pool: l0vk.VkDescriptorPool = null,

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

pub fn init(info: *const RenderPassInitInfo) !RenderPass {
    var system = info.system;
    var swapchain = &info.window.swapchain.swapchain;

    var render_pass: l0vk.VkRenderPass = undefined;
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

    var framebuffers: []l0vk.VkFramebuffer = undefined;
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
        l0vk.vkDestroyDescriptorPool(system.logical_device, self.imgui_descriptor_pool, null);
        cimgui.ImGui_ImplVulkan_Shutdown();
        cimgui.ImGui_ImplGlfw_Shutdown();
        cimgui.igDestroyContext(null);
    }

    var i: usize = 0;
    while (i < self.framebuffers.len) : (i += 1) {
        l0vk.vkDestroyFramebuffer(system.logical_device, self.framebuffers[i], null);
    }
    allocator.free(self.framebuffers);

    i = 0;
    while (i < self.images.len) : (i += 1) {
        self.images[i].color.deinit(system.logical_device);
    }
    allocator.free(self.images);

    l0vk.vkDestroyRenderPass(system.logical_device, self.render_pass, null);
}

pub fn setup_imgui(self: *RenderPass, system: *VulkanSystem, window: *Window) !void {
    self.imgui_enabled = true;

    // --- Descriptor pool.

    const pool_sizes = [_]l0vk.VkDescriptorPoolSize{
        .{
            .type = .sampler,
            .descriptorCount = 1000,
        },
        .{
            .type = .combined_image_sampler,
            .descriptorCount = 1000,
        },
        .{
            .type = .sampled_image,
            .descriptorCount = 1000,
        },
        .{
            .type = .storage_image,
            .descriptorCount = 1000,
        },
        .{
            .type = .uniform_texel_buffer,
            .descriptorCount = 1000,
        },
        .{
            .type = .storage_texel_buffer,
            .descriptorCount = 1000,
        },
        .{
            .type = .uniform_buffer,
            .descriptorCount = 1000,
        },
        .{
            .type = .storage_buffer,
            .descriptorCount = 1000,
        },
        .{
            .type = .uniform_buffer_dynamic,
            .descriptorCount = 1000,
        },
        .{
            .type = .storage_buffer_dynamic,
            .descriptorCount = 1000,
        },
        .{
            .type = .input_attachment,
            .descriptorCount = 1000,
        },
    };

    const pool_info = l0vk.VkDescriptorPoolCreateInfo{
        .flags = .{
            .free_descriptor_set = true,
        },
        .maxSets = 1000,
        .poolSizes = &pool_sizes,
    };

    self.imgui_descriptor_pool = try l0vk.vkCreateDescriptorPool(
        system.logical_device,
        &pool_info,
        null,
    );

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
        .MSAASamples = @import("vulkan").VK_SAMPLE_COUNT_1_BIT,
    };
    _ = cimgui.ImGui_ImplVulkan_Init(@ptrCast(&vulkan_init_info), @ptrCast(self.render_pass));

    // --- Load fonts.

    var command_pool = system.command_pool;
    var command_buffer = window.swapchain.swapchain.a_command_buffers[0];

    try l0vk.vkResetCommandPool(
        system.logical_device,
        command_pool,
        .{},
    );

    const cb_begin_info = l0vk.VkCommandBufferBeginInfo{
        .flags = .{
            .one_time_submit = true,
        },
    };
    try l0vk.vkBeginCommandBuffer(command_buffer, &cb_begin_info);

    _ = cimgui.ImGui_ImplVulkan_CreateFontsTexture(@ptrCast(command_buffer));

    const end_info = l0vk.VkSubmitInfo{
        .commandBuffers = &[_]l0vk.VkCommandBuffer{
            command_buffer,
        },
        .waitSemaphores = &[_]l0vk.VkSemaphore{},
        .signalSemaphores = &[_]l0vk.VkSemaphore{},
        .pWaitDstStageMask = null,
    };

    try l0vk.vkEndCommandBuffer(command_buffer);
    try l0vk.vkQueueSubmit(system.graphics_queue, 1, &end_info, null);
    try l0vk.vkDeviceWaitIdle(system.logical_device);

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
    command_buffer: l0vk.VkCommandBuffer,
    image_index: u32,
    clear: bool,
) void {
    var clear_values = [_]l0vk.VkClearValue{
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
    var clear_values_slice: []l0vk.VkClearValue = undefined;
    if (clear) {
        clear_values_slice = clear_values[0..];
    } else {
        clear_values_slice = clear_values[0..0];
    }

    var framebuffer = self.framebuffers[0];
    if (self.framebuffers.len > 1) {
        framebuffer = self.framebuffers[image_index];
    }

    const render_pass_info = l0vk.VkRenderPassBeginInfo{
        .renderPass = self.render_pass,
        .framebuffer = framebuffer,
        .renderArea = l0vk.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = self.render_area.width, .height = self.render_area.height },
        },
        .clearValues = clear_values_slice,
    };

    l0vk.vkCmdBeginRenderPass(
        command_buffer,
        &render_pass_info,
        ._inline,
    );
}

pub fn end(self: *RenderPass, command_buffer: l0vk.VkCommandBuffer) void {
    if (self.imgui_enabled) {
        cimgui.ImGui_ImplVulkan_RenderDrawData(
            cimgui.igGetDrawData(),
            @ptrCast(command_buffer),
            null,
        );
    }

    l0vk.vkCmdEndRenderPass(command_buffer);
}

pub fn resize_callback(
    self: *RenderPass,
    allocator: std.mem.Allocator,
    system: *VulkanSystem,
    swapchain: *Swapchain,
    new_render_area: RenderArea,
) !void {
    var i: usize = 0;
    while (i < self.framebuffers.len) : (i += 1) {
        l0vk.vkDestroyFramebuffer(system.logical_device, self.framebuffers[i], null);
    }
    allocator.free(self.framebuffers);

    self.framebuffers = try create_basic_primary_framebuffers(system, swapchain, self.render_pass);
    self.render_area = new_render_area;
}

// --- Vulkan renderpass. {{{1

const AttachmentAndRef = struct {
    attachment: l0vk.VkAttachmentDescription,
    ref: l0vk.VkAttachmentReference,
};

fn build_color_attachment(swapchain: *Swapchain, clear: bool) !AttachmentAndRef {
    var loadOp: l0vk.VkAttachmentLoadOp = .clear;
    if (!clear) {
        loadOp = .load;
    }
    var initialLayout: l0vk.VkImageLayout = .undefined;
    if (!clear) {
        initialLayout = .color_attachment_optimal;
    }
    var finalLayout: l0vk.VkImageLayout = .color_attachment_optimal;
    if (!clear) {
        finalLayout = .present_src_khr;
    }

    const color_attachment = l0vk.VkAttachmentDescription{
        .format = swapchain.swapchain_image_format,
        // The top-level render pass doesn't need multisampling.
        .samples = .VK_SAMPLE_COUNT_1_BIT,
        .loadOp = loadOp,
        .storeOp = .store,
        .stencilLoadOp = .dont_care,
        .stencilStoreOp = .dont_care,
        .initialLayout = initialLayout,
        .finalLayout = finalLayout,
    };

    const color_attachment_ref = l0vk.VkAttachmentReference{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };

    return AttachmentAndRef{
        .attachment = color_attachment,
        .ref = color_attachment_ref,
    };
}

fn build_basic_primary_renderpass(
    system: *VulkanSystem,
    swapchain: *Swapchain,
    clear: bool,
) !l0vk.VkRenderPass {
    // --- Attachments.

    const color_attachment = try build_color_attachment(swapchain, clear);
    const color_attachments = [_]l0vk.VkAttachmentReference{color_attachment.ref};

    // --- Subpass.

    const subpass = l0vk.VkSubpassDescription{
        .pipelineBindPoint = .graphics,
        .colorAttachments = &color_attachments,
        .inputAttachments = &[0]l0vk.VkAttachmentReference{},
        .resolveAttachments = &[0]l0vk.VkAttachmentReference{},
        .pDepthStencilAttachment = null,
        .preserveAttachments = &[0]u32{},
    };

    // ---

    const attachments = [_]l0vk.VkAttachmentDescription{
        color_attachment.attachment,
    };

    const render_pass_info = l0vk.VkRenderPassCreateInfo{
        .attachments = &attachments,
        .subpasses = &[_]l0vk.VkSubpassDescription{subpass},
        .dependencies = &[_]l0vk.VkSubpassDependency{},
    };

    const render_pass = try l0vk.vkCreateRenderPass(
        system.logical_device,
        &render_pass_info,
        null,
    );

    return render_pass;
}

// --- }}}1

// --- Framebuffers. {{{1

fn create_basic_primary_framebuffers(
    system: *VulkanSystem,
    swapchain: *Swapchain,
    render_pass: l0vk.VkRenderPass,
) ![]l0vk.VkFramebuffer {
    const allocator = system.allocator;
    var framebuffers = try allocator.alloc(l0vk.VkFramebuffer, swapchain.swapchain_image_views.len);
    errdefer allocator.free(framebuffers);

    var i: usize = 0;
    while (i < swapchain.swapchain_image_views.len) : (i += 1) {
        const attachments = [_]l0vk.VkImageView{
            swapchain.swapchain_image_views[i],
        };

        var framebuffer_info = l0vk.VkFramebufferCreateInfo{
            .renderPass = render_pass,
            .attachments = &attachments,
            .width = swapchain.swapchain_extent.width,
            .height = swapchain.swapchain_extent.height,
            .layers = 1,
        };

        framebuffers[i] = try l0vk.vkCreateFramebuffer(
            system.logical_device,
            &framebuffer_info,
            null,
        );
    }

    return framebuffers;
}

fn create_basic_deferred_framebuffers(
    allocator: std.mem.Allocator,
    system: *VulkanSystem,
    width: u32,
    height: u32,
    image_view: l0vk.VkImageView,
    render_pass: l0vk.VkRenderPass,
) ![]l0vk.VkFramebuffer {
    var framebuffers = try allocator.alloc(l0vk.VkFramebuffer, 1);
    errdefer allocator.free(framebuffers);

    const attachments = [_]l0vk.VkImageView{
        image_view,
    };

    var framebuffer_info = l0vk.VkFramebufferCreateInfo{
        .renderPass = render_pass,
        .attachments = &attachments,
        .width = width,
        .height = height,
        .layers = 1,
    };

    framebuffers[0] = try l0vk.vkCreateFramebuffer(
        system.logical_device,
        &framebuffer_info,
        null,
    );

    return framebuffers;
}

// --- }}}1
