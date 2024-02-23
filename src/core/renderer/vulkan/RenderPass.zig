const std = @import("std");
const du = @import("debug_utils");
const l0vk = @import("../layer0/vulkan/vulkan.zig");
const Window = @import("../../Window.zig");
const cimgui = @import("cimgui");
const Swapchain = @import("./Swapchain.zig");
const VulkanSystem = @import("./VulkanSystem.zig");
const AttachmentKind = @import("./resource.zig").AttachmentKind;
const RenderPassInfo = @import("../RenderPass.zig").RenderPassInfo;
const buffer = @import("buffer.zig");
const RenderPassTag = @import("../RenderPass.zig").RenderPassTag;

// --- [[ Renderpass system ]]

pub const RenderpassHandle = usize;

pub const RenderpassSystem = struct {
    renderpasses: std.ArrayList(Renderpass),
    free_renderpass_indices: std.ArrayList(usize),
    rp_map: std.StringHashMap(RenderpassHandle),

    pub fn init(allocator_: std.mem.Allocator) RenderpassSystem {
        return .{
            .renderpasses = std.ArrayList(Renderpass).init(allocator_),
            .free_renderpass_indices = std.ArrayList(usize).init(allocator_),
            .rp_map = std.StringHashMap(RenderpassHandle).init(allocator_),
        };
    }

    pub fn deinit(self: *RenderpassSystem, system: *VulkanSystem) void {
        var i: usize = 0;

        while (i < self.free_renderpass_indices.items.len) : (i += 1) {
            const idx = self.free_renderpass_indices.items[i];
            _ = self.renderpasses.swapRemove(idx);
        }

        i = 0;
        while (i < self.renderpasses.items.len) : (i += 1) {
            const rp = &self.renderpasses.items[i];
            rp.deinit(system);
        }

        self.renderpasses.deinit();
        self.free_renderpass_indices.deinit();
        self.rp_map.deinit();
    }

    pub fn deinit_renderpass(
        self: *RenderpassSystem,
        system: *VulkanSystem,
        handle: RenderpassHandle,
    ) !void {
        const rp = self.renderpasses.items[handle];
        const rp_name = rp.name;

        try self.free_renderpass_indices.append(handle);
        _ = self.rp_map.remove(rp_name);
        self.renderpasses.items[handle].deinit(system);
    }

    pub fn create_renderpass(
        self: *RenderpassSystem,
        info: *const Renderpass.CreateInfo,
    ) !RenderpassHandle {
        const rp = try Renderpass.init(info);

        var handle: usize = undefined;
        if (self.free_renderpass_indices.items.len > 0) {
            handle = self.free_renderpass_indices.pop();
            self.renderpasses.items[handle] = rp;
        } else {
            handle = self.renderpasses.items.len;
            try self.renderpasses.append(rp);
        }

        try self.rp_map.put(info.name, handle);
        return handle;
    }

    pub fn get_renderpass_from_handle(self: *RenderpassSystem, handle: RenderpassHandle) *Renderpass {
        return &self.renderpasses.items[handle];
    }

    pub fn get_renderpass_from_name(self: *RenderpassSystem, name: []const u8) ?*Renderpass {
        if (self.rp_map.get(name)) |handle| {
            return self.get_renderpass_from_handle(handle);
        }

        return null;
    }

    pub fn pre_begin(
        self: *RenderpassSystem,
        window: *Window,
        current_frame: usize,
        handle: RenderpassHandle,
    ) void {
        const rp_ptr = &self.renderpasses.items[handle];
        rp_ptr.pre_begin(window, current_frame);
    }

    pub fn begin(
        self: *RenderpassSystem,
        system: *VulkanSystem,
        handle: RenderpassHandle,
        command_buffer: l0vk.VkCommandBuffer,
    ) void {
        const rp_ptr = &self.renderpasses.items[handle];
        rp_ptr.begin(system, command_buffer);
    }

    pub fn end(
        self: *RenderpassSystem,
        system: *VulkanSystem,
        handle: RenderpassHandle,
        command_buffer: l0vk.VkCommandBuffer,
    ) void {
        const rp_ptr = &self.renderpasses.items[handle];
        rp_ptr.end(system, command_buffer);
    }
};

// --- [[ Renderpass ]]

pub const ImGuiConfigFlags = packed struct(c_int) {
    nav_enable_keyboard: bool = false,
    nav_enable_gamepad: bool = false,
    nav_enable_set_mouse_pos: bool = false,
    nav_no_capture_keyboard: bool = false,

    no_mouse: bool = false,
    no_mouse_cursor_change: bool = false,
    docking_enabled: bool = false,
    viewports_enabled: bool = false,

    _: u24 = 0,
};

pub const RenderArea = struct {
    width: u32,
    height: u32,
};

pub const Renderpass = struct {
    name: []const u8,
    color_attachment_infos: []Attachment,
    color_attachments: []l0vk.VkRenderingAttachmentInfo,
    depth_attachment_infos: []Attachment,
    depth_attachments: []l0vk.VkRenderingAttachmentInfo,
    clear_color: [4]f32,
    imgui_info: ImguiInfo,

    window: *Window,
    render_info: *l0vk.VkRenderingInfo,

    pub const Attachment = struct {
        kind: AttachmentKind,
        format: l0vk.VkFormat,
        image_view: l0vk.VkImageView,
    };

    const ImguiInfo = union(enum) { disabled, enabled: struct {
        descriptor_pool: l0vk.VkDescriptorPool,
    } };

    const Self = @This();

    pub const CreateInfo = struct {
        name: []const u8,
        system: *VulkanSystem,
        window: *Window,
        attachments: []const Attachment,
        clear_color: [4]f32,
        enable_imgui: bool,
    };

    pub fn init(info: *const Renderpass.CreateInfo) !Self {
        const allocator = info.system.allocator;

        const render_info = try allocator.create(l0vk.VkRenderingInfo);

        const swapchain_extent = info.window.swapchain.swapchain.swapchain_extent;
        const render_area = RenderArea{
            .width = swapchain_extent.width,
            .height = swapchain_extent.height,
        };

        // ---

        var num_color_attachments: usize = 0;
        var num_depth_attachments: usize = 0;
        var i: usize = 0;
        while (i < info.attachments.len) : (i += 1) {
            const attachment_ptr = &info.attachments[i];
            switch (attachment_ptr.kind) {
                .color, .color_final => num_color_attachments += 1,
                .depth => num_depth_attachments += 1,
            }
        }

        var color_attachment_infos = try allocator.alloc(
            Attachment,
            num_color_attachments,
        );
        var color_attachments = try allocator.alloc(
            l0vk.VkRenderingAttachmentInfo,
            num_color_attachments,
        );
        var depth_attachment_infos = try allocator.alloc(
            Attachment,
            num_depth_attachments,
        );
        var depth_attachments = try allocator.alloc(
            l0vk.VkRenderingAttachmentInfo,
            num_depth_attachments,
        );

        var num_color_attachments_populated: usize = 0;
        var num_depth_attachments_populated: usize = 0;
        i = 0;
        while (i < info.attachments.len) : (i += 1) {
            const attachment_ptr = &info.attachments[i];
            switch (attachment_ptr.kind) {
                .color_final => {
                    const idx = num_color_attachments_populated;
                    color_attachment_infos[idx] = attachment_ptr.*;
                    color_attachments[idx] = l0vk.VkRenderingAttachmentInfo{
                        .imageView = undefined,
                        .imageLayout = .color_attachment_optimal,
                        .loadOp = .clear,
                        .storeOp = .store,
                        .clearValue = .{ .color = .{ .float32 = info.clear_color } },

                        .resolveImageLayout = .undefined,
                        .resolveImageView = null,
                    };
                    num_color_attachments_populated += 1;
                },
                .color => {
                    const idx = num_color_attachments_populated;
                    color_attachment_infos[idx] = attachment_ptr.*;
                    color_attachments[idx] = l0vk.VkRenderingAttachmentInfo{
                        .imageView = attachment_ptr.image_view,
                        .imageLayout = .color_attachment_optimal,
                        .loadOp = .clear,
                        .storeOp = .store,
                        .clearValue = .{ .color = .{ .float32 = info.clear_color } },

                        .resolveImageLayout = .undefined,
                        .resolveImageView = null,
                    };
                    num_color_attachments_populated += 1;
                },
                .depth => {
                    const idx = num_depth_attachments_populated;
                    depth_attachment_infos[idx] = attachment_ptr.*;
                    depth_attachments[idx] = l0vk.VkRenderingAttachmentInfo{
                        .imageView = attachment_ptr.image_view,
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
                    num_depth_attachments_populated += 1;
                },
            }
        }

        if (color_attachments.len > 1) {
            du.log(
                "renderpass",
                .warn,
                "can't have multiple color attachments (tried to init '{s}' with {d})",
                .{ info.name, color_attachments.len },
            );
            @panic("remove me");
        }

        const depth_attachment_ptr = if (num_depth_attachments > 0) &depth_attachments[0] else null;

        var imgui_info = ImguiInfo{ .disabled = {} };
        if (info.enable_imgui) {
            const config_flags = ImGuiConfigFlags{ .docking_enabled = true };
            imgui_info = try setup_imgui(
                info.system,
                info.window,
                @bitCast(config_flags),
            );
        }

        render_info.* = l0vk.VkRenderingInfo{
            .renderArea = l0vk.VkRect2D{
                .offset = .{ .x = 0, .y = 0 },
                .extent = .{ .width = render_area.width, .height = render_area.height },
            },

            .layerCount = 1,
            .colorAttachments = color_attachments,
            .pDepthAttachment = depth_attachment_ptr,
            .pStencilAttachment = null,
        };

        return Renderpass{
            .name = info.name,
            .color_attachment_infos = color_attachment_infos,
            .color_attachments = color_attachments,
            .depth_attachment_infos = depth_attachment_infos,
            .depth_attachments = depth_attachments,
            .clear_color = info.clear_color,
            .imgui_info = imgui_info,

            .window = info.window,
            .render_info = render_info,
        };
    }

    pub fn deinit(self: *Self, system: *VulkanSystem) void {
        // TODO:
        // Normally the callback should be removed, but since right now we only deinit
        // renderpasses when the program ends it's okay.
        //
        // self.window.window_size_pixels.remove_callback(self.window_resize_callback_handle) catch unreachable;

        switch (self.imgui_info) {
            .disabled => {},
            .enabled => {
                l0vk.vkDestroyDescriptorPool(system.logical_device, self.imgui_info.enabled.descriptor_pool, null);
                cimgui.ImGui_ImplVulkan_Shutdown();
                cimgui.ImGui_ImplGlfw_Shutdown();
                cimgui.igDestroyContext(null);
            },
        }

        const allocator = system.allocator;

        allocator.destroy(self.render_info);

        allocator.free(self.color_attachment_infos);
        allocator.free(self.color_attachments);
        allocator.free(self.depth_attachment_infos);
        allocator.free(self.depth_attachments);
    }

    pub fn setup_imgui(
        system: *VulkanSystem,
        window: *Window,
        config_flags: c_int,
    ) !ImguiInfo {
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

        const imgui_descriptor_pool = try l0vk.vkCreateDescriptorPool(
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
            .DescriptorPool = @ptrCast(imgui_descriptor_pool),
            .MinImageCount = @intCast(window.swapchain.swapchain.swapchain_images.len),
            .ImageCount = @intCast(window.swapchain.swapchain.swapchain_images.len),
            .MSAASamples = @import("vulkan").VK_SAMPLE_COUNT_1_BIT,
            .UseDynamicRendering = true,
            .ColorAttachmentFormat = @intFromEnum(window.swapchain.swapchain.swapchain_image_format),
        };
        _ = cimgui.ImGui_ImplVulkan_Init(@ptrCast(&vulkan_init_info), @ptrCast(l0vk.VK_NULL_HANDLE));

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

        return ImguiInfo{
            .enabled = .{
                .descriptor_pool = imgui_descriptor_pool,
            },
        };
    }

    pub fn pre_begin(self: *Self, window: *Window, current_frame: usize) void {
        var i: usize = 0;
        while (i < self.color_attachment_infos.len) : (i += 1) {
            const attachment_ptr = &self.color_attachments[i];
            const info_ptr = &self.color_attachment_infos[i];

            if (info_ptr.kind == .color_final) {
                attachment_ptr.imageView = window.swapchain.swapchain.swapchain_image_views[current_frame];
            }
        }
    }

    pub fn begin(self: *Self, system: *VulkanSystem, command_buffer: l0vk.VkCommandBuffer) void {
        l0vk.vkCmdBeginRendering(
            system.instance,
            command_buffer,
            self.render_info,
        ) catch unreachable;
    }

    pub fn end(self: *Self, system: *VulkanSystem, command_buffer: l0vk.VkCommandBuffer) void {
        switch (self.imgui_info) {
            .disabled => {},
            .enabled => {
                cimgui.ImGui_ImplVulkan_RenderDrawData(
                    cimgui.igGetDrawData(),
                    @ptrCast(command_buffer),
                    @ptrCast(l0vk.VK_NULL_HANDLE),
                );
            },
        }

        l0vk.vkCmdEndRendering(system.instance, command_buffer);
    }
};
