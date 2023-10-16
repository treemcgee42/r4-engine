const std = @import("std");
const vulkan = @import("vulkan");
const Core = @import("../Core.zig");
const Renderer = @import("./Renderer.zig");
const VirtualPipeline = Renderer.Pipeline;
const VirtualPipelineHandle = Renderer.PipelineHandle;
const Swapchain = @import("./Swapchain.zig");

allocator: std.mem.Allocator,
commands: std.MultiArrayList(Command),
extra_data: std.ArrayList(usize),

const CommandBuffer = @This();

pub fn init(allocator: std.mem.Allocator) !CommandBuffer {
    return .{
        .allocator = allocator,
        .commands = std.MultiArrayList(Command){},
        .extra_data = std.ArrayList(usize).init(allocator),
    };
}

pub fn deinit(self: *CommandBuffer) void {
    self.commands.deinit(self.allocator);
    self.extra_data.deinit();
}

const Command = struct {
    kind: CommandKind,
    data: usize,

    const CommandKind = enum {
        // `data` is a `PipelineHandle`.
        bind_pipeline,
        // `data` is the number of vertices to draw.
        draw,
        // `data` is a `RenderPassHandle`.
        begin_render_pass,
        // `data` is a `RenderPassHandle`.
        end_render_pass,
    };
};

pub fn reset(self: *CommandBuffer) void {
    self.commands.len = 0;
    self.extra_data.items.len = 0;
}

pub fn execute_command(self: *CommandBuffer, command_handle: usize, renderer: *Renderer) !void {
    const kind = self.commands.items(.kind)[command_handle];
    const data = self.commands.items(.data)[command_handle];

    switch (kind) {
        .bind_pipeline => {
            try execute_bind_pipeline(renderer, data);
        },
        .draw => {
            execute_draw(renderer, data);
        },
        else => unreachable,
    }
}

fn execute_bind_pipeline(
    renderer: *Renderer,
    virtual_pipeline_handle: VirtualPipelineHandle,
) !void {
    const current_frame_context = renderer.current_frame_context.?;

    // --- Query the vulkan pipeline.

    const virtual_pipeline = renderer.get_pipeline_from_handle(virtual_pipeline_handle);
    const virtual_renderpass_handle = virtual_pipeline.render_pass;
    const vk_renderpass_handle = renderer.render_graph.?.rp_handle_to_real_rp.get(virtual_renderpass_handle).?;
    const vk_renderpass = renderer.system.get_renderpass_from_handle(vk_renderpass_handle).render_pass;
    const vk_pipeline = try renderer.system.pipeline_system.query(
        renderer,
        virtual_pipeline,
        vk_renderpass,
    );

    // ---

    vulkan.vkCmdBindPipeline(
        current_frame_context.command_buffer,
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
    vulkan.vkCmdSetViewport(current_frame_context.command_buffer, 0, 1, &viewport);

    const scissor = vulkan.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swapchain.swapchain.swapchain_extent,
    };
    vulkan.vkCmdSetScissor(current_frame_context.command_buffer, 0, 1, &scissor);
}

fn execute_draw(renderer: *Renderer, num_vertices: usize) void {
    vulkan.vkCmdDraw(renderer.current_frame_context.?.command_buffer, @intCast(num_vertices), 1, 0, 0);
}
