const std = @import("std");
const vulkan = @import("vulkan");
const cimgui = @import("cimgui");
pub const Pipeline = @import("./pipeline.zig").Pipeline;
const CommandBuffer = @import("CommandBuffer.zig");
const VulkanSystem = @import("vulkan/VulkanSystem.zig");
const RenderPass = @import("RenderPass.zig");
const RenderGraph = @import("RenderGraph.zig");
pub const RenderPassInfo = RenderPass.RenderPassInfo;
const Swapchain = @import("Swapchain.zig");
const Window = @import("../Window.zig");

allocator: std.mem.Allocator,

system: VulkanSystem,
pipelines: std.ArrayList(Pipeline),
render_passes: std.ArrayList(RenderPass),
render_graph: ?RenderGraph,
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

    const render_passes = std.ArrayList(RenderPass).init(allocator);
    const command_buffer = try CommandBuffer.init(allocator);

    return .{
        .allocator = allocator,

        .system = system,
        .pipelines = std.ArrayList(Pipeline).init(allocator),
        .render_passes = render_passes,
        .render_graph = null,
        .command_buffer = command_buffer,

        .current_frame_context = null,
    };
}

pub fn deinit(self: *Renderer) void {
    if (self.render_graph != null) {
        self.render_graph.?.deinit();
    }

    var i: usize = 0;
    while (i < self.render_passes.items.len) : (i += 1) {
        self.render_passes.items[i].deinit(self);
    }
    self.render_passes.deinit();

    self.pipelines.deinit();

    self.system.deinit(self.allocator);

    self.command_buffer.deinit();
}

pub fn begin_imgui(self: *Renderer) void {
    _ = self;
    cimgui.ImGui_ImplVulkan_NewFrame();
    cimgui.ImGui_ImplGlfw_NewFrame();

    cimgui.igNewFrame();
}

pub fn end_imgui(self: *Renderer) void {
    _ = self;

    cimgui.igRender();
}

pub fn begin_frame(self: *Renderer, window: *Window) !void {
    self.command_buffer.reset();

    self.current_frame_context = .{
        .command_buffer = undefined,
        .image_index = undefined,
        .window = window,
        .render_pass = null,
    };
}

pub fn end_frame(self: *Renderer, window: *Window) !void {
    if (self.render_graph == null) {
        self.render_graph = try RenderGraph.init(self, &self.command_buffer);
        try self.render_graph.?.compile(self);
    }

    var swapchain = &window.swapchain.swapchain;
    var system = self.system;

    // --- Wait for the previous frame to finish.

    var result = vulkan.vkWaitForFences(
        self.system.logical_device,
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
    try self.render_graph.?.execute(self);

    const current_frame_context = self.current_frame_context.?;

    // --- End command buffer.

    result = vulkan.vkEndCommandBuffer(current_frame_context.command_buffer);
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
        self.system.graphics_queue,
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

    result = vulkan.vkQueuePresentKHR(self.system.present_queue, &present_info);
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
}

pub const RenderPassHandle = usize;

pub fn create_renderpass(self: *Renderer, info: *RenderPassInfo) !RenderPassHandle {
    const rp = try RenderPass.init(info);
    try self.render_passes.append(rp);
    return self.render_passes.items.len - 1;
}

pub fn get_renderpass_from_handle(self: *const Renderer, handle: RenderPassHandle) *RenderPass {
    return &self.render_passes.items[handle];
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

pub const PipelineHandle = usize;

pub fn create_pipeline(self: *Renderer, pipeline: Pipeline) !PipelineHandle {
    try self.pipelines.append(pipeline);
    return self.pipelines.items.len - 1;
}

pub fn get_pipeline_from_handle(self: *Renderer, handle: PipelineHandle) *Pipeline {
    return &self.pipelines.items[handle];
}

pub fn bind_pipeline(self: *Renderer, pipeline_handle: PipelineHandle) !void {
    try self.command_buffer.commands.append(self.allocator, .{
        .kind = .bind_pipeline,
        .data = pipeline_handle,
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

pub const Resource = struct {
    kind: enum {
        color_texture,
        /// What will be shown on screen.
        final_texture,
    },
    width: u32,
    height: u32,
};
