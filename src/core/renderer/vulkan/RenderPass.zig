const std = @import("std");
const du = @import("debug_utils");
const l0vk = @import("../layer0/vulkan/vulkan.zig");
const Window = @import("../../Window.zig");
const cimgui = @import("cimgui");
const Swapchain = @import("./Swapchain.zig");
const VulkanSystem = @import("./VulkanSystem.zig");
const RenderPassInfo = @import("../RenderPass.zig").RenderPassInfo;
const buffer = @import("buffer.zig");
const RenderPassTag = @import("../RenderPass.zig").RenderPassTag;

pub const Renderpass = union(enum) {
    static: StaticRenderpass,
    dynamic: DynamicRenderpass,
};

pub const RenderpassHandle = usize;

pub const RenderpassSystem = struct {
    renderpasses: std.ArrayList(Renderpass),

    pub fn init(allocator_: std.mem.Allocator) RenderpassSystem {
        return .{
            .renderpasses = std.ArrayList(Renderpass).init(allocator_),
        };
    }

    pub fn deinit(self: *RenderpassSystem, system: *VulkanSystem) void {
        var i: usize = 0;
        while (i < self.renderpasses.items.len) : (i += 1) {
            switch (self.renderpasses.items[i]) {
                .static => |*rp| rp.deinit(system.allocator, system),
                .dynamic => |*rp| rp.deinit(system),
            }
        }

        self.renderpasses.deinit();
    }

    pub fn create_static_renderpass(
        self: *RenderpassSystem,
        info: *const StaticRenderpass.CreateInfo,
    ) !RenderpassHandle {
        const rp = try StaticRenderpass.init(info);
        try self.renderpasses.append(.{ .static = rp });
        return self.renderpasses.items.len - 1;
    }

    pub fn create_dynamic_renderpass(
        self: *RenderpassSystem,
        info: *const DynamicRenderpass.CreateInfo,
    ) !RenderpassHandle {
        const rp = try DynamicRenderpass.init(info.*);
        try self.renderpasses.append(.{ .dynamic = rp });
        return self.renderpasses.items.len - 1;
    }

    pub fn get_renderpass_from_handle(self: *RenderpassSystem, handle: RenderpassHandle) *Renderpass {
        return &self.renderpasses.items[handle];
    }

    pub fn resize_all(self: *RenderpassSystem, system: *VulkanSystem, window: *Window) !void {
        const new_window_size = window.size();
        const new_render_area = .{
            .width = new_window_size.width,
            .height = new_window_size.height,
        };

        var i: usize = 0;
        while (i < self.renderpasses.items.len) : (i += 1) {
            var rp_ptr = &self.renderpasses.items[i];
            switch (rp_ptr.*) {
                .static => {
                    try rp_ptr.static.resize_callback(
                        system.allocator,
                        system,
                        &window.swapchain.swapchain,
                        new_render_area,
                    );
                },
                .dynamic => {
                    rp_ptr.dynamic.render_info.renderArea = .{
                        .offset = .{ .x = 0, .y = 0 },
                        .extent = new_render_area,
                    };
                },
            }
        }
    }
};

// --- Common

pub const Image = union(enum) {
    color: buffer.ColorImage,
    depth: buffer.DepthImage,
};

const ImagesManager = struct {
    map: std.StringHashMap(Image),

    fn init(allocator: std.mem.Allocator) ImagesManager {
        return .{
            .map = std.StringHashMap(Image).init(allocator),
        };
    }

    fn deinit(self: *ImagesManager, system: *const VulkanSystem) void {
        var images_iter = self.map.valueIterator();
        while (images_iter.next()) |image| {
            switch (image.*) {
                Image.color => |color_image| {
                    color_image.deinit(system.logical_device, system.vma_allocator);
                },
                Image.depth => |depth_image| {
                    depth_image.deinit(system.logical_device, system.vma_allocator);
                },
            }
        }
        self.map.deinit();
    }
};

pub const RenderArea = struct {
    width: u32,
    height: u32,
};

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

fn create_render_to_image_images(
    system: *VulkanSystem,
    render_area_width: u32,
    render_area_height: u32,
    swapchain_image_format: l0vk.VkFormat,
    depth_buffered: bool,
) !ImagesManager {
    var images = ImagesManager.init(system.allocator);

    const color_image = try buffer.ColorImage.init(
        system.physical_device,
        system.logical_device,
        system.vma_allocator,
        render_area_width,
        render_area_height,
        @intFromEnum(swapchain_image_format),
        @bitCast(l0vk.VkSampleCountFlags{ .bit_1 = true }),
        @bitCast(l0vk.VkImageUsageFlags{ .color_attachment = true, .sampled = true }),
    );
    try images.map.put("color", .{ .color = color_image });
    system.tmp_image = color_image; // TODO remove

    if (depth_buffered) {
        const depth_image = try buffer.DepthImage.init(
            system.physical_device,
            system.logical_device,
            system.vma_allocator,
            render_area_width,
            render_area_height,
            1,
        );
        try images.map.put("depth", .{ .depth = depth_image });
    }

    return images;
}

// --- StaticRenderpass

pub const StaticRenderpass = struct {
    render_pass: l0vk.VkRenderPass,

    images: ImagesManager,
    framebuffers: []l0vk.VkFramebuffer,
    render_area: RenderArea,
    load_op_clear: bool,

    imgui_enabled: bool,
    imgui_descriptor_pool: l0vk.VkDescriptorPool = null,

    name: []const u8,
    tag: RenderPassTag,
    clear_color: [4]f32 = .{ 0, 0, 0, 1 },

    pub const CreateInfo = struct {
        system: *VulkanSystem,
        window: *Window,

        imgui_enabled: bool = false,
        imgui_config_flags: c_int = 0,
        tag: RenderPassTag,
        render_area: RenderArea,
        depth_buffered: bool = false,
        name: []const u8,
    };

    pub fn init(info: *const CreateInfo) !StaticRenderpass {
        const system = info.system;
        const swapchain = &info.window.swapchain.swapchain;

        var load_op_clear = true;

        var render_pass: l0vk.VkRenderPass = undefined;
        switch (info.tag) {
            .basic_primary => {
                if (info.imgui_enabled) {
                    load_op_clear = false;
                }
                render_pass = try build_basic_primary_renderpass(system, swapchain, load_op_clear);
            },
            .render_to_image => {
                render_pass = try build_render_to_image_renderpass(system, swapchain, info.depth_buffered);
            },
        }

        var images = ImagesManager.init(system.allocator);
        switch (info.tag) {
            .basic_primary => {
                // Just use the swapchain images.
            },
            .render_to_image => {
                images.deinit(system);
                images = try create_render_to_image_images(
                    system,
                    info.render_area.width,
                    info.render_area.height,
                    swapchain.swapchain_image_format,
                    info.depth_buffered,
                );
            },
        }

        var framebuffers: []l0vk.VkFramebuffer = undefined;
        switch (info.tag) {
            .basic_primary => {
                framebuffers = try create_basic_primary_framebuffers(system, swapchain, render_pass);
            },
            .render_to_image => {
                framebuffers = try create_render_to_image_framebuffers(system, &images, render_pass);
            },
        }

        var to_return = StaticRenderpass{
            .render_pass = render_pass,

            .images = images,
            .framebuffers = framebuffers,
            .render_area = info.render_area,
            .load_op_clear = load_op_clear,

            // Potentially updated before returning.
            .imgui_enabled = false,
            .name = info.name,
            .tag = info.tag,
        };

        if (info.imgui_enabled) {
            try to_return.setup_imgui(system, info.window, info.imgui_config_flags);
            du.log("renderer", .info, "imgui initialized", .{});
        }

        return to_return;
    }

    pub fn deinit(self: *StaticRenderpass, allocator: std.mem.Allocator, system: *VulkanSystem) void {
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

        self.images.deinit(system);

        l0vk.vkDestroyRenderPass(system.logical_device, self.render_pass, null);
    }

    pub fn setup_imgui(
        self: *StaticRenderpass,
        system: *VulkanSystem,
        window: *Window,
        config_flags: c_int,
    ) !void {
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
        const io = cimgui.igGetIO();
        io.*.ConfigFlags = config_flags;
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

        const command_pool = system.command_pool;
        const command_buffer = window.swapchain.swapchain.a_command_buffers[0];

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
        self: *StaticRenderpass,
        command_buffer: l0vk.VkCommandBuffer,
        image_index: u32,
        clear: bool,
    ) void {
        var clear_values = [_]l0vk.VkClearValue{
            .{
                .color = .{
                    .float32 = self.clear_color,
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

    pub fn end(self: *StaticRenderpass, command_buffer: l0vk.VkCommandBuffer) void {
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
        self: *StaticRenderpass,
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

        const depth_buffered = self.images.map.contains("depth");

        if (self.tag != .basic_primary) {
            self.images.deinit(system);
        }

        // ---

        switch (self.tag) {
            .basic_primary => {
                self.framebuffers = try create_basic_primary_framebuffers(
                    system,
                    swapchain,
                    self.render_pass,
                );
            },
            .render_to_image => {
                self.images = try create_render_to_image_images(
                    system,
                    new_render_area.width,
                    new_render_area.height,
                    swapchain.swapchain_image_format,
                    depth_buffered,
                );
                system.tmp_renderer.?.ui.?.tmp_uploaded_image = false;
                self.framebuffers = try create_render_to_image_framebuffers(
                    system,
                    &self.images,
                    self.render_pass,
                );
            },
        }

        // ---

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

    fn build_render_to_image_color_attachment(swapchain: *Swapchain) !AttachmentAndRef {
        const color_attachment = l0vk.VkAttachmentDescription{
            .format = swapchain.swapchain_image_format,
            .samples = .VK_SAMPLE_COUNT_1_BIT,
            .loadOp = .clear,
            .storeOp = .store,
            .stencilLoadOp = .dont_care,
            .stencilStoreOp = .dont_care,
            .initialLayout = .undefined,
            .finalLayout = .shader_read_only_optimal,
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

    fn build_render_to_image_depth_attachment() !AttachmentAndRef {
        const depth_attachment = l0vk.VkAttachmentDescription{
            .flags = .{},
            .format = .d32_sfloat, // hardcoded for now
            .samples = .VK_SAMPLE_COUNT_1_BIT,
            .loadOp = .clear,
            .storeOp = .store,
            .stencilLoadOp = .clear,
            .stencilStoreOp = .dont_care,
            .initialLayout = .undefined,
            .finalLayout = .depth_stencil_attachment_optimal,
        };

        const depth_attachment_ref = l0vk.VkAttachmentReference{
            .attachment = 1,
            .layout = .depth_stencil_attachment_optimal,
        };

        return AttachmentAndRef{
            .attachment = depth_attachment,
            .ref = depth_attachment_ref,
        };
    }

    fn build_render_to_image_renderpass(
        system: *VulkanSystem,
        swapchain: *Swapchain,
        with_depth_attachment: bool,
    ) !l0vk.VkRenderPass {
        // --- Attachments.

        const color_attachment = try build_render_to_image_color_attachment(swapchain);
        const color_attachments = [_]l0vk.VkAttachmentReference{color_attachment.ref};

        var depth_attachment: ?AttachmentAndRef = null;
        if (with_depth_attachment) {
            depth_attachment = try build_render_to_image_depth_attachment();
        }

        // --- Subpass.

        const pDepthStencilAttachment: ?*l0vk.VkAttachmentReference = if (with_depth_attachment) &depth_attachment.?.ref else null;

        const subpass = l0vk.VkSubpassDescription{
            .pipelineBindPoint = .graphics,
            .colorAttachments = &color_attachments,
            .inputAttachments = &[0]l0vk.VkAttachmentReference{},
            .resolveAttachments = &[0]l0vk.VkAttachmentReference{},
            .pDepthStencilAttachment = pDepthStencilAttachment,
            .preserveAttachments = &[0]u32{},
        };

        // ---

        var attachments = [2]l0vk.VkAttachmentDescription{ undefined, undefined };
        var pAttachments: []l0vk.VkAttachmentDescription = undefined;
        attachments[0] = color_attachment.attachment;
        if (with_depth_attachment) {
            attachments[1] = depth_attachment.?.attachment;
            pAttachments = &attachments;
        } else {
            pAttachments = attachments[0..1];
        }

        const color_dependency = l0vk.VkSubpassDependency{
            .srcSubpass = l0vk.VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = .{
                .color_attachment_output = true,
            },
            .srcAccessMask = .{},
            .dstStageMask = .{
                .color_attachment_output = true,
            },
            .dstAccessMask = .{
                .color_attachment_write = true,
            },
        };

        const depth_dependency = l0vk.VkSubpassDependency{
            .srcSubpass = l0vk.VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = .{
                .early_fragment_tests = true,
                .late_fragment_tests = true,
            },
            .srcAccessMask = .{},
            .dstStageMask = .{
                .early_fragment_tests = true,
                .late_fragment_tests = true,
            },
            .dstAccessMask = .{
                .depth_stencil_attachment_write = true,
            },
        };

        var dependencies = [2]l0vk.VkSubpassDependency{ undefined, undefined };
        var pDependencies: []l0vk.VkSubpassDependency = undefined;
        dependencies[0] = color_dependency;
        if (with_depth_attachment) {
            dependencies[1] = depth_dependency;
            pDependencies = &dependencies;
        } else {
            pDependencies = dependencies[0..1];
        }

        const render_pass_info = l0vk.VkRenderPassCreateInfo{
            .attachments = pAttachments,
            .subpasses = &[_]l0vk.VkSubpassDescription{subpass},
            .dependencies = pDependencies,
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

    const CreateRenderToImageFramebuffersError = error{
        missing_color_image,
    };

    fn create_render_to_image_framebuffers(
        system: *VulkanSystem,
        images: *const ImagesManager,
        render_pass: l0vk.VkRenderPass,
    ) ![]l0vk.VkFramebuffer {
        const allocator = system.allocator;
        var framebuffers = try allocator.alloc(l0vk.VkFramebuffer, 1);
        errdefer allocator.free(framebuffers);

        var attachments = [2]l0vk.VkImageView{ undefined, undefined };
        var pAttachments: []l0vk.VkImageView = undefined;
        const color_image_ptr = images.map.get("color") orelse {
            return CreateRenderToImageFramebuffersError.missing_color_image;
        };
        attachments[0] = color_image_ptr.color.image_view;
        if (images.map.get("depth")) |depth_image| {
            attachments[1] = depth_image.depth.image_view;
            pAttachments = &attachments;
        } else {
            pAttachments = attachments[0..1];
        }

        var framebuffer_info = l0vk.VkFramebufferCreateInfo{
            .renderPass = render_pass,
            .attachments = pAttachments,
            .width = color_image_ptr.color.image.width,
            .height = color_image_ptr.color.image.height,
            .layers = 1,
        };

        framebuffers[0] = try l0vk.vkCreateFramebuffer(
            system.logical_device,
            &framebuffer_info,
            null,
        );

        du.log("l1vk", .info, "created 1 framebuffer with {d} attachments", .{pAttachments.len});

        return framebuffers;
    }
};

// --- DynamicRenderpass

pub const DynamicRenderpass = struct {
    system: *VulkanSystem,
    images: ImagesManager,
    attachments: std.StringHashMap(AttachmentInfo),
    color_attachments: []l0vk.VkRenderingAttachmentInfo,
    render_info: l0vk.VkRenderingInfo,
    clear_color: [4]f32 = .{ 0, 0, 0, 1 },
    name: []const u8,

    pub const CreateInfo = struct {
        system: *VulkanSystem,
        window: *Window,

        imgui_enabled: bool = false,
        imgui_config_flags: c_int = 0,
        tag: RenderPassTag,
        render_area: RenderArea,
        depth_buffered: bool = false,
        name: []const u8,
        clear_color: [4]f32 = .{ 0, 0, 0, 1 },
    };

    pub const AttachmentInfo = struct {
        rendering_info: l0vk.VkRenderingAttachmentInfo,
        format: l0vk.VkFormat,
    };

    pub fn init(info: CreateInfo) !DynamicRenderpass {
        const system = info.system;
        const swapchain = &info.window.swapchain.swapchain;

        // --- Images

        var images = ImagesManager.init(system.allocator);
        switch (info.tag) {
            .basic_primary => {
                // Just use the swapchain images.
            },
            .render_to_image => {
                images.deinit(system);
                images = try create_render_to_image_images(
                    system,
                    info.render_area.width,
                    info.render_area.height,
                    swapchain.swapchain_image_format,
                    info.depth_buffered,
                );
            },
        }

        // --- Attachments.

        var attachments = std.StringHashMap(AttachmentInfo).init(system.allocator);

        switch (info.tag) {
            .basic_primary => {
                @panic("not implemented");
            },
            .render_to_image => {
                const color_attachment_info = l0vk.VkRenderingAttachmentInfo{
                    .imageView = images.map.get("color").?.color.image_view,
                    .imageLayout = .color_attachment_optimal,
                    .loadOp = .clear,
                    .storeOp = .store,
                    .clearValue = .{ .color = .{ .float32 = info.clear_color } },

                    .resolveImageLayout = .undefined,
                    .resolveImageView = null,
                };
                try attachments.put(
                    "color",
                    .{
                        .rendering_info = color_attachment_info,
                        .format = swapchain.swapchain_image_format,
                    },
                );

                if (info.depth_buffered) {
                    const depth_attachment_info = l0vk.VkRenderingAttachmentInfo{
                        .imageView = images.map.get("depth").?.depth.image_view,
                        .imageLayout = .depth_stencil_attachment_optimal,
                        .loadOp = .clear,
                        .storeOp = .store,
                        .clearValue = .{
                            .depthStencil = .{
                                .depth = 1.0,
                                .stencil = 0,
                            },
                        },

                        .resolveImageLayout = .undefined,
                        .resolveImageView = null,
                    };
                    try attachments.put(
                        "depth",
                        .{
                            .rendering_info = depth_attachment_info,
                            .format = .d32_sfloat,
                        },
                    );
                }
            },
        }

        // --- RenderInfo

        var color_attachments = try system.allocator.alloc(l0vk.VkRenderingAttachmentInfo, 1);
        color_attachments[0] = attachments.get("color").?.rendering_info;

        const depth_attachment_struct_ptr = attachments.getPtr("depth");
        const pDepthAttachment = if (depth_attachment_struct_ptr != null) &depth_attachment_struct_ptr.?.rendering_info else null;

        const render_info = l0vk.VkRenderingInfo{
            .renderArea = l0vk.VkRect2D{
                .offset = .{ .x = 0, .y = 0 },
                .extent = .{ .width = info.render_area.width, .height = info.render_area.height },
            },

            .layerCount = 1,
            .colorAttachments = color_attachments,
            .pDepthAttachment = pDepthAttachment,
            .pStencilAttachment = null,
        };

        // ---

        return DynamicRenderpass{
            .system = system,
            .images = images,
            .attachments = attachments,
            .color_attachments = color_attachments,
            .render_info = render_info,
            .clear_color = info.clear_color,
            .name = info.name,
        };
    }

    pub fn deinit(self: *DynamicRenderpass, system: *VulkanSystem) void {
        self.images.deinit(system);
        self.attachments.deinit();
        system.allocator.free(self.color_attachments);
    }

    pub fn set_color_clear_value(self: *DynamicRenderpass, color: [4]f32) void {
        self.clear_color = color;
        self.color_attachments[0].clearValue = .{ .color = .{ .float32 = color } };
    }

    pub fn begin(self: *DynamicRenderpass, command_buffer: l0vk.VkCommandBuffer) !void {
        try l0vk.vkCmdBeginRendering(self.system.instance, command_buffer, &self.render_info);
    }

    pub fn end(self: *DynamicRenderpass, command_buffer: l0vk.VkCommandBuffer) void {
        l0vk.vkCmdEndRendering(self.system.instance, command_buffer);
    }
};
