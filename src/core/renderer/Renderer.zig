const std = @import("std");
const vulkan = @import("vulkan");
const cimgui = @import("cimgui");
const PipelineSystem = @import("./pipeline.zig").PipelineSystem;
const CommandBuffer = @import("CommandBuffer.zig");
const VulkanSystem = @import("vulkan/VulkanSystem.zig");
const RenderPass = @import("RenderPass.zig");
const Swapchain = @import("Swapchain.zig");
const Window = @import("../Window.zig");

allocator: std.mem.Allocator,

backend: Backend,
system: union {
    vulkan: VulkanSystem,
},
pipeline_system: PipelineSystem,
render_passes: std.ArrayList(RenderPass),
command_buffer: CommandBuffer,

current_frame_context: ?CurrentFrameContext,

pub const Backend = enum {
    vulkan,
};

pub const CurrentFrameContext = struct {
    render_pass: ?*RenderPass,
    command_buffer: vulkan.VkCommandBuffer,
    image_index: u32,
    window: *Window,
};

const Renderer = @This();

pub fn init(allocator: std.mem.Allocator, backend: Backend) !Renderer {
    const system = switch (backend) {
        .vulkan => try VulkanSystem.init(allocator),
    };

    const pipeline_system = try PipelineSystem.init(allocator);
    const render_passes = std.ArrayList(RenderPass).init(allocator);
    const command_buffer = try CommandBuffer.init(allocator);

    return .{
        .allocator = allocator,

        .backend = backend,
        .system = .{ .vulkan = system },
        .pipeline_system = pipeline_system,
        .render_passes = render_passes,
        .command_buffer = command_buffer,

        .current_frame_context = null,
    };
}

pub fn deinit(self: *Renderer) void {
    var i: usize = 0;
    while (i < self.render_passes.items.len) : (i += 1) {
        self.render_passes.items[i].deinit(self);
    }
    self.render_passes.deinit();

    self.pipeline_system.deinit(self);

    switch (self.backend) {
        .vulkan => {
            self.system.vulkan.deinit(self.allocator);
        },
    }
    self.command_buffer.deinit();
}

pub fn begin_imgui(self: *Renderer) void {
    switch (self.backend) {
        .vulkan => {
            cimgui.ImGui_ImplVulkan_NewFrame();
        },
    }
    cimgui.ImGui_ImplGlfw_NewFrame();

    cimgui.igNewFrame();
}

pub fn end_imgui(self: *Renderer) void {
    _ = self;

    cimgui.igRender();
}

pub fn begin_frame(self: *Renderer, window: *Window) !void {
    switch (self.backend) {
        .vulkan => {
            var swapchain = &window.swapchain.swapchain.vulkan;
            var system = self.system.vulkan;

            // --- Wait for the previous frame to finish.

            var result = vulkan.vkWaitForFences(
                self.system.vulkan.logical_device,
                1,
                &swapchain.in_flight_fences[swapchain.current_frame],
                vulkan.VK_TRUE,
                std.math.maxInt(u64),
            );
            if (result != vulkan.VK_SUCCESS) {
                unreachable;
            }

            // --- Acquire the next image.

            var image_index: u32 = undefined;
            result = vulkan.vkAcquireNextImageKHR(
                system.logical_device,
                swapchain.swapchain,
                std.math.maxInt(u64),
                swapchain.image_available_semaphores[swapchain.current_frame],
                @ptrCast(vulkan.VK_NULL_HANDLE),
                &image_index,
            );
            if (result != vulkan.VK_SUCCESS and result != vulkan.VK_SUBOPTIMAL_KHR) {
                switch (result) {
                    vulkan.VK_ERROR_OUT_OF_DATE_KHR => {
                        try window.recreate_swapchain_callback(self);
                        return self.begin_frame(window);
                    },
                    else => unreachable,
                }
            }

            // --- Reset the fence if submitting work.

            result = vulkan.vkResetFences(
                system.logical_device,
                1,
                &swapchain.in_flight_fences[swapchain.current_frame],
            );
            if (result != vulkan.VK_SUCCESS) {
                unreachable;
            }

            // ---

            var p_command_buffer = &system.command_buffers[swapchain.current_frame];

            result = vulkan.vkResetCommandBuffer(p_command_buffer.*, 0);
            if (result != vulkan.VK_SUCCESS) {
                unreachable;
            }

            // --- Begin command buffer.

            const begin_info = vulkan.VkCommandBufferBeginInfo{
                .sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                .flags = 0,
                .pInheritanceInfo = null,
                .pNext = null,
            };

            result = vulkan.vkBeginCommandBuffer(p_command_buffer.*, &begin_info);
            if (result != vulkan.VK_SUCCESS) {
                unreachable;
            }

            // ---

            self.current_frame_context = .{
                .command_buffer = p_command_buffer.*,
                .image_index = image_index,
                .window = window,
                .render_pass = null,
            };
        },
    }
}

pub fn end_frame(self: *Renderer) !void {
    const current_frame_context = self.current_frame_context.?;

    switch (self.backend) {
        .vulkan => {
            try self.command_buffer.execute(self);

            var swapchain = &current_frame_context.window.swapchain.swapchain.vulkan;
            var p_command_buffer = &current_frame_context.command_buffer;

            // --- End command buffer.

            var result = vulkan.vkEndCommandBuffer(current_frame_context.command_buffer);
            if (result != vulkan.VK_SUCCESS) {
                unreachable;
            }

            // --- Submit command buffer.

            const wait_semaphores = [_]vulkan.VkSemaphore{swapchain.image_available_semaphores[swapchain.current_frame]};
            const wait_stages = [_]vulkan.VkPipelineStageFlags{
                vulkan.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            };
            const signal_semaphores = [_]vulkan.VkSemaphore{
                swapchain.render_finished_semaphores[swapchain.current_frame],
            };

            const submit_info = vulkan.VkSubmitInfo{
                .sType = vulkan.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                .waitSemaphoreCount = wait_semaphores.len,
                .pWaitSemaphores = wait_semaphores[0..].ptr,
                .pWaitDstStageMask = wait_stages[0..].ptr,
                .commandBufferCount = 1,
                .pCommandBuffers = p_command_buffer,
                .signalSemaphoreCount = signal_semaphores.len,
                .pSignalSemaphores = signal_semaphores[0..].ptr,

                .pNext = null,
            };

            result = vulkan.vkQueueSubmit(
                self.system.vulkan.graphics_queue,
                1,
                &submit_info,
                swapchain.in_flight_fences[swapchain.current_frame],
            );
            if (result != vulkan.VK_SUCCESS) {
                unreachable;
            }

            // --- Present.

            const swapchains = [_]vulkan.VkSwapchainKHR{swapchain.swapchain};
            const present_info = vulkan.VkPresentInfoKHR{
                .sType = vulkan.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
                .waitSemaphoreCount = 1,
                .pWaitSemaphores = signal_semaphores[0..].ptr,
                .swapchainCount = swapchains.len,
                .pSwapchains = swapchains[0..].ptr,
                .pImageIndices = &current_frame_context.image_index,

                .pResults = null,
                .pNext = null,
            };

            result = vulkan.vkQueuePresentKHR(self.system.vulkan.present_queue, &present_info);
            if (result != vulkan.VK_SUCCESS) {
                switch (result) {
                    vulkan.VK_ERROR_OUT_OF_DATE_KHR => {
                        try current_frame_context.window.recreate_swapchain_callback(self);
                    },
                    vulkan.VK_SUBOPTIMAL_KHR => {
                        try current_frame_context.window.recreate_swapchain_callback(self);
                    },
                    else => unreachable,
                }
            }

            if (current_frame_context.window.framebuffer_resized) {
                current_frame_context.window.framebuffer_resized = false;
                try current_frame_context.window.recreate_swapchain_callback(self);
            }

            swapchain.current_frame = (swapchain.current_frame + 1) % Swapchain.max_frames_in_flight;
        },
    }
}

pub const RenderPassHandle = usize;

pub fn create_renderpass(self: *Renderer, window: *Window) !RenderPassHandle {
    const rp = try RenderPass.init(self, window);
    try self.render_passes.append(rp);
    return self.render_passes.items.len - 1;
}

/// Simply passes `num_vertices` to the shader. No assumptions are made about the
/// positioning of these vertices. A typical usecase is to instead use the index
/// of the vertex (`gl_VertexIndex`) to do something in the shader.
pub fn draw(self: *Renderer, num_vertices: usize) !void {
    try self.command_buffer.commands.append(self.allocator, .{
        .kind = .draw,
        .data = num_vertices,
    });
}

pub fn bind_pipeline(self: *Renderer, pipeline: PipelineSystem.PipelineHandle) !void {
    try self.command_buffer.commands.append(self.allocator, .{
        .kind = .bind_pipeline,
        .data = pipeline,
    });
}

pub fn begin_renderpass(self: *Renderer, render_pass: RenderPassHandle) !void {
    try self.command_buffer.commands.append(self.allocator, .{
        .kind = .begin_render_pass,
        .data = render_pass,
    });
}

pub fn end_renderpass(self: *Renderer, render_pass: RenderPassHandle) !void {
    try self.command_buffer.commands.append(self.allocator, .{
        .kind = .end_render_pass,
        .data = render_pass,
    });
}
