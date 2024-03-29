const std = @import("std");
const vulkan = @import("vulkan");
const Core = @import("../Core.zig");
const Renderer = @import("./Renderer.zig");
const VirtualPipeline = Renderer.Pipeline;
const VirtualPipelineHandle = Renderer.PipelineHandle;
const Swapchain = @import("vulkan/Swapchain.zig");
const RenderPassHandle = Renderer.RenderPassHandle;
const VertexBuffer = @import("vulkan/buffer.zig").VertexBuffer;
const PushConstants = @import("./Scene.zig").PushConstants;

allocator: std.mem.Allocator,
commands: std.ArrayList(Command),
extra_data: std.ArrayList(usize),

const CommandBuffer = @This();

pub fn init(allocator: std.mem.Allocator) !CommandBuffer {
    return .{
        .allocator = allocator,
        .commands = std.ArrayList(Command).init(allocator),
        .extra_data = std.ArrayList(usize).init(allocator),
    };
}

pub fn deinit(self: *CommandBuffer) void {
    self.commands.deinit();
    self.extra_data.deinit();
}

pub const UploadPushConstantsCommand = struct {
    push_constants: PushConstants,
    pipeline: VirtualPipelineHandle,
};

const Command = union(enum) {
    bind_pipeline: VirtualPipelineHandle,
    // Number of vertices to draw.
    draw: usize,
    begin_render_pass: RenderPassHandle,
    end_render_pass: RenderPassHandle,
    bind_vertex_buffer: vulkan.VkBuffer,
    upload_push_constants: UploadPushConstantsCommand,
};

pub fn reset(self: *CommandBuffer) void {
    self.commands.items.len = 0;
    self.extra_data.items.len = 0;
}

pub fn execute_command(
    self: *CommandBuffer,
    command_handle: usize,
    renderer: *Renderer,
    command_buffer: vulkan.VkCommandBuffer,
) !void {
    const command = self.commands.items[command_handle];

    switch (command) {
        .bind_pipeline => {
            try execute_bind_pipeline(renderer, command.bind_pipeline, command_buffer);
        },
        .draw => {
            execute_draw(renderer, command.draw, command_buffer);
        },
        .bind_vertex_buffer => {
            try execute_bind_vertex_buffer(
                renderer,
                command.bind_vertex_buffer,
                command_buffer,
            );
        },
        .upload_push_constants => {
            try execute_upload_push_constants(
                renderer,
                command.upload_push_constants,
                command_buffer,
            );
        },
        else => {
            @panic("Unimplemented command");
        },
    }
}

fn execute_upload_push_constants(
    renderer: *Renderer,
    push_constants_data: UploadPushConstantsCommand,
    command_buffer: vulkan.VkCommandBuffer,
) !void {
    const virtual_pipeline = renderer.get_pipeline_from_handle(push_constants_data.pipeline);
    const virtual_renderpass_handle = virtual_pipeline.render_pass;
    const vk_renderpass_handle = renderer.render_graph.?.rp_handle_to_real_rp.get(virtual_renderpass_handle).?;
    const vk_renderpass = renderer.system.get_renderpass_from_handle(vk_renderpass_handle);
    const pipeline_layout = (try renderer.system.pipeline_system.query(
        renderer,
        virtual_pipeline,
        vk_renderpass,
    )).pipeline_layout;

    vulkan.vkCmdPushConstants(
        command_buffer,
        pipeline_layout,
        vulkan.VK_SHADER_STAGE_VERTEX_BIT,
        0,
        @sizeOf(PushConstants),
        &push_constants_data.push_constants,
    );
}

fn execute_bind_vertex_buffer(
    renderer: *Renderer,
    vertex_buffers: vulkan.VkBuffer,
    command_buffer: vulkan.VkCommandBuffer,
) !void {
    const current_frame_context = renderer.current_frame_context.?;
    _ = current_frame_context;

    var bufs = [_]vulkan.VkBuffer{vertex_buffers};
    var offsets = [_]vulkan.VkDeviceSize{0};

    vulkan.vkCmdBindVertexBuffers(
        command_buffer,
        0,
        1,
        bufs[0..].ptr,
        offsets[0..].ptr,
    );
}

fn execute_bind_pipeline(renderer: *Renderer, virtual_pipeline_handle: VirtualPipelineHandle, command_buffer: vulkan.VkCommandBuffer) !void {
    const current_frame_context = renderer.current_frame_context.?;
    _ = current_frame_context;

    // --- Query the vulkan pipeline.

    const virtual_pipeline = renderer.get_pipeline_from_handle(virtual_pipeline_handle);
    const virtual_renderpass_handle = virtual_pipeline.render_pass;
    const vk_renderpass_handle = renderer.render_graph.?.rp_handle_to_real_rp.get(virtual_renderpass_handle).?;
    const vk_renderpass = renderer.system.get_renderpass_from_handle(vk_renderpass_handle);
    const vk_pipeline = (try renderer.system.pipeline_system.query(
        renderer,
        virtual_pipeline,
        vk_renderpass,
    )).pipeline;

    // ---

    vulkan.vkCmdBindPipeline(
        command_buffer,
        vulkan.VK_PIPELINE_BIND_POINT_GRAPHICS,
        vk_pipeline,
    );

    const swapchain = renderer.current_frame_context.?.window.swapchain;
    const viewport = vulkan.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(swapchain.swapchain.swapchain_extent.width), // TODO
        .height = @floatFromInt(swapchain.swapchain.swapchain_extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    vulkan.vkCmdSetViewport(command_buffer, 0, 1, &viewport);

    const scissor = vulkan.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swapchain.swapchain.swapchain_extent,
    };
    vulkan.vkCmdSetScissor(command_buffer, 0, 1, &scissor);
}

fn execute_draw(renderer: *Renderer, num_vertices: usize, command_buffer: vulkan.VkCommandBuffer) void {
    _ = renderer;
    vulkan.vkCmdDraw(command_buffer, @intCast(num_vertices), 1, 0, 0);
}
