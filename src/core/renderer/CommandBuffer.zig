const std = @import("std");
const vulkan = @import("vulkan");
const Pipeline = @import("./pipeline.zig").Pipeline;
const PipelineHandle = @import("pipeline.zig").PipelineSystem.PipelineHandle;
const Core = @import("../Core.zig");
const Renderer = @import("./Renderer.zig");
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

pub fn execute(self: *CommandBuffer, renderer: *Renderer) !void {
    var i: usize = 0;
    while (i < self.commands.len) : (i += 1) {
        switch (self.commands.items(.kind)[i]) {
            .bind_pipeline => {
                execute_bind_pipeline(renderer, self.commands.items(.data)[i]);
            },
            .draw => {
                execute_draw(renderer, self.commands.items(.data)[i]);
            },
            .begin_render_pass => {
                try execute_begin_renderpass(renderer, self.commands.items(.data)[i]);
            },
            .end_render_pass => {
                try execute_end_renderpass(renderer, self.commands.items(.data)[i]);
            },
        }
    }

    self.commands.len = 0;
}

fn execute_bind_pipeline(
    renderer: *Renderer,
    pipeline_handle: PipelineHandle,
) void {
    const current_frame_context = renderer.current_frame_context.?;

    switch (renderer.backend) {
        .vulkan => {
            vulkan.vkCmdBindPipeline(
                current_frame_context.command_buffer,
                vulkan.VK_PIPELINE_BIND_POINT_GRAPHICS,
                renderer.pipeline_system.pipelines.get(pipeline_handle).?.vulkan,
            );

            const swapchain = renderer.current_frame_context.?.window.swapchain;
            const viewport = vulkan.VkViewport{
                .x = 0.0,
                .y = 0.0,
                .width = @floatFromInt(swapchain.swapchain.vulkan.swapchain_extent.width),
                .height = @floatFromInt(swapchain.swapchain.vulkan.swapchain_extent.height),
                .minDepth = 0.0,
                .maxDepth = 1.0,
            };
            vulkan.vkCmdSetViewport(current_frame_context.command_buffer, 0, 1, &viewport);

            const scissor = vulkan.VkRect2D{
                .offset = .{ .x = 0, .y = 0 },
                .extent = swapchain.swapchain.vulkan.swapchain_extent,
            };
            vulkan.vkCmdSetScissor(current_frame_context.command_buffer, 0, 1, &scissor);
        },
    }
}

fn execute_draw(renderer: *Renderer, num_vertices: usize) void {
    switch (renderer.backend) {
        .vulkan => {
            vulkan.vkCmdDraw(renderer.current_frame_context.?.command_buffer, @intCast(num_vertices), 1, 0, 0);
        },
    }
}

fn execute_begin_renderpass(renderer: *Renderer, render_pass_handle: Renderer.RenderPassHandle) !void {
    const swapchain = &renderer.current_frame_context.?.window.swapchain;

    const rp = &renderer.render_passes.items[render_pass_handle];
    try rp.begin(renderer, swapchain);
    renderer.current_frame_context.?.render_pass = rp;
}

fn execute_end_renderpass(renderer: *Renderer, render_pass_handle: Renderer.RenderPassHandle) !void {
    try renderer.render_passes.items[render_pass_handle].end(renderer);
    renderer.current_frame_context.?.render_pass = null;
}
