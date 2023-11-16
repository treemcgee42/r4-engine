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
const Ui = @import("./Ui.zig");
const VulkanRenderPass = VulkanSystem.RenderPass;
const VulkanRenderPassHandle = VulkanSystem.RenderPassHandle;
const VertexBuffer = @import("vulkan/buffer.zig").VertexBuffer;

allocator: std.mem.Allocator,

system: VulkanSystem,
pipelines: std.ArrayList(Pipeline),
render_passes: std.ArrayList(RenderPass),
resource_system: ResourceSystem,
render_graph: ?RenderGraph,
command_buffer: CommandBuffer,

current_frame_context: ?CurrentFrameContext,
ui: ?Ui,

pub const Backend = enum {
    vulkan,
};

pub const CurrentFrameContext = struct {
    image_index: u32,

    command_buffer_a: vulkan.VkCommandBuffer,
    command_buffer_b: vulkan.VkCommandBuffer,

    image_available_semaphore: VulkanSystem.SemaphoreHandle,
    a_semaphore: VulkanSystem.SemaphoreHandle,
    b_semaphore: VulkanSystem.SemaphoreHandle,
    render_finished_semaphore: VulkanSystem.SemaphoreHandle,

    fence: VulkanSystem.FenceHandle,

    window: *Window,

    render_pass: ?*RenderPass,
};

const Renderer = @This();

pub fn init(allocator: std.mem.Allocator, backend: Backend) !Renderer {
    var system = switch (backend) {
        .vulkan => try VulkanSystem.init(allocator),
    };

    const render_passes = std.ArrayList(RenderPass).init(allocator);
    const command_buffer = try CommandBuffer.init(allocator);

    return .{
        .allocator = allocator,

        .system = system,
        .pipelines = std.ArrayList(Pipeline).init(allocator),
        .render_passes = render_passes,
        .resource_system = ResourceSystem.init(allocator),
        .render_graph = null,
        .command_buffer = command_buffer,

        .current_frame_context = null,
        .ui = null,
    };
}

pub fn deinit(self: *Renderer) void {
    if (self.render_graph != null) {
        self.render_graph.?.deinit(self);
    }

    var i: usize = 0;
    while (i < self.render_passes.items.len) : (i += 1) {
        self.render_passes.items[i].deinit(self);
    }
    self.render_passes.deinit();
    self.resource_system.deinit();

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
        .image_index = undefined,

        .command_buffer_a = undefined,
        .command_buffer_b = undefined,

        .image_available_semaphore = undefined,
        .a_semaphore = undefined,
        .b_semaphore = undefined,
        .render_finished_semaphore = undefined,

        .fence = undefined,

        .window = window,

        .render_pass = undefined,
    };
}

pub fn end_frame(self: *Renderer, window: *Window) !void {
    if (self.render_graph == null) {
        self.render_graph = try RenderGraph.init(self, &self.command_buffer);
        try self.render_graph.?.compile(self);
    }

    var swapchain = &window.swapchain.swapchain;
    var system = self.system;

    var image_available_semaphore = swapchain.current_image_available_semaphore();
    var render_finished_semaphore = swapchain.current_render_finished_semaphore();
    var fence = swapchain.current_in_flight_fence();

    // --- Wait for the previous frame to finish.

    var result = vulkan.vkWaitForFences(
        self.system.logical_device,
        1,
        system.get_fence_from_handle(fence),
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
        system.get_semaphore_from_handle(image_available_semaphore).*,
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
        system.get_fence_from_handle(fence),
    );
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }

    // ---

    var command_buffer_a = swapchain.a_command_buffers[swapchain.current_frame];
    var command_buffer_b = swapchain.b_command_buffers[swapchain.current_frame];

    result = vulkan.vkResetCommandBuffer(command_buffer_a, 0);
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }
    result = vulkan.vkResetCommandBuffer(command_buffer_b, 0);
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }

    // ---

    self.current_frame_context = .{
        .image_index = image_index,

        .command_buffer_a = command_buffer_a,
        .command_buffer_b = command_buffer_b,

        .image_available_semaphore = image_available_semaphore,
        .a_semaphore = swapchain.a_semaphores[swapchain.current_frame],
        .b_semaphore = swapchain.b_semaphores[swapchain.current_frame],
        .render_finished_semaphore = render_finished_semaphore,

        .fence = fence,

        .window = window,

        .render_pass = null,
    };

    try self.render_graph.?.execute(self);

    const current_frame_context = self.current_frame_context.?;

    // --- Present.

    const swapchains = [_]vulkan.VkSwapchainKHR{swapchain.swapchain};
    const present_info = vulkan.VkPresentInfoKHR{
        .sType = vulkan.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = system.get_semaphore_from_handle(render_finished_semaphore),
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

// ---

pub const RenderPassHandle = struct {
    virtual_rp_idx: usize,
    physical_rp_handle: ?VulkanRenderPassHandle,
};

pub fn create_renderpass(self: *Renderer, info: *RenderPassInfo) !RenderPassHandle {
    const rp = try RenderPass.init(info);
    try self.render_passes.append(rp);
    return .{
        .virtual_rp_idx = self.render_passes.items.len - 1,
        .physical_rp_handle = null,
    };
}

pub fn get_renderpass_from_handle(
    self: *const Renderer,
    handle: RenderPassHandle,
) *RenderPass {
    return &self.render_passes.items[handle.virtual_rp_idx];
}

// ---

/// Simply passes `num_vertices` to the shader. No assumptions are made about the
/// positioning of these vertices. A typical usecase is to instead use the index
/// of the vertex (`gl_VertexIndex`) to do something in the shader.
pub fn draw(self: *Renderer, num_vertices: usize) !void {
    try self.command_buffer.commands.append(.{
        .draw = num_vertices,
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
    try self.command_buffer.commands.append(.{
        .bind_pipeline = pipeline_handle,
    });
}

pub fn bind_vertex_buffers(
    self: *Renderer,
    buffers: []vulkan.VkBuffer,
) !void {
    try self.command_buffer.commands.append(.{
        .bind_vertex_buffers = buffers,
    });
}

inline fn get_vulkan_rp_from_virtual_rp_handle(
    self: *Renderer,
    virtual_rp_handle: RenderPassHandle,
) ?*VulkanRenderPass {
    if (self.render_graph == null) {
        return null;
    }

    const vk_rp_handle = self.render_graph.?.rp_handle_to_real_rp.get(virtual_rp_handle);
    if (vk_rp_handle == null) {
        return null;
    }

    return self.system.get_renderpass_from_handle(vk_rp_handle.?);
}

pub fn set_renderpass_clear_color(
    self: *Renderer,
    virtual_rp_handle: RenderPassHandle,
    color: [4]f32,
) void {
    if (self.render_graph == null) {
        return;
    }

    const vk_rp_ptr = self.get_vulkan_rp_from_virtual_rp_handle(virtual_rp_handle);
    vk_rp_ptr.?.*.clear_color = color;
}

pub fn begin_renderpass(self: *Renderer, render_pass: RenderPassHandle) !void {
    try self.command_buffer.commands.append(.{
        .begin_render_pass = render_pass,
    });
}

pub fn end_renderpass(self: *Renderer, render_pass: RenderPassHandle) !void {
    try self.command_buffer.commands.append(.{
        .end_render_pass = render_pass,
    });
}

// ---

pub const ResourceInfo = struct {
    kind: enum {
        color_texture,
        /// What will be shown on screen.
        final_texture,
    },
    width: u32,
    height: u32,
};

pub const Resource = usize;

pub const ResourceSystem = struct {
    resources: std.ArrayList(ResourceInfo),

    pub fn init(allocator: std.mem.Allocator) ResourceSystem {
        return .{
            .resources = std.ArrayList(ResourceInfo).init(allocator),
        };
    }

    pub fn deinit(self: *ResourceSystem) void {
        self.resources.deinit();
    }

    pub fn get_resource_from_handle(self: *ResourceSystem, handle: usize) *ResourceInfo {
        return &self.resources.items[handle];
    }

    pub fn create_resource(self: *ResourceSystem, info: ResourceInfo) !Resource {
        try self.resources.append(info);
        return self.resources.items.len - 1;
    }
};

// ---

pub fn enable_ui(self: *Renderer, window: *Window, config_flags: Ui.ConfigFlags) !void {
    self.ui = try Ui.init(self, window, config_flags);
    self.system.tmp_renderer = self;
}
