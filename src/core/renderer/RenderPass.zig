const std = @import("std");
const cimgui = @import("cimgui");
const vulkan = @import("vulkan");
const VulkanRenderPass = @import("vulkan//RenderPass.zig");
const Context = @import("./Context.zig");
const Swapchain = @import("./Swapchain.zig");
const RendererApiContext = @import("./renderer_api.zig").RendererApiContext;
const Window = @import("../Window.zig");

render_pass: union {
    vulkan: VulkanRenderPass,
},

const RenderPass = @This();

pub fn init(allocator: std.mem.Allocator, context: *Context, swapchain: *Swapchain) !RenderPass {
    const render_pass = try switch (context.backend) {
        .vulkan => VulkanRenderPass.init_basic_primary(.{
            .allocator = allocator,
            .system = &context.system.vulkan,
            .swapchain = &swapchain.swapchain.vulkan,
        }),
    };

    return .{
        .render_pass = .{
            .vulkan = render_pass,
        },
    };
}

pub fn deinit(self: *RenderPass, allocator: std.mem.Allocator, context: *Context) void {
    switch (context.backend) {
        .vulkan => {
            self.render_pass.vulkan.deinit(allocator, &context.system.vulkan);
        },
    }
}

pub fn recreate_swapchain_callback(
    self: *RenderPass,
    allocator: std.mem.Allocator,
    context: *Context,
    swapchain: *Swapchain,
) !void {
    switch (context.backend) {
        .vulkan => {
            try self.render_pass.vulkan.recreate_swapchain_callback(allocator, &context.system.vulkan, &swapchain.swapchain.vulkan);
        },
    }
}

pub fn setup_imgui(self: *RenderPass, context: *Context, window: *Window) !void {
    switch (context.backend) {
        .vulkan => {
            try self.render_pass.vulkan.setup_imgui(&context.system.vulkan, window);
        },
    }
}

pub fn begin(self: *RenderPass, swapchain: *Swapchain, context: RendererApiContext) !void {
    self.render_pass.vulkan.begin(&swapchain.swapchain.vulkan, context.command_buffer, context.image_index);
}

pub fn end(self: *RenderPass, context: RendererApiContext) !void {
    self.render_pass.vulkan.end(context.command_buffer);
}

pub fn draw(self: *RenderPass, swapchain: *Swapchain, context: RendererApiContext) !void {
    vulkan.vkCmdBindPipeline(context.command_buffer, vulkan.VK_PIPELINE_BIND_POINT_GRAPHICS, self.render_pass.vulkan.pipeline);

    const viewport = vulkan.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(swapchain.swapchain.vulkan.swapchain_extent.width),
        .height = @floatFromInt(swapchain.swapchain.vulkan.swapchain_extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    vulkan.vkCmdSetViewport(context.command_buffer, 0, 1, &viewport);

    const scissor = vulkan.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swapchain.swapchain.vulkan.swapchain_extent,
    };
    vulkan.vkCmdSetScissor(context.command_buffer, 0, 1, &scissor);

    vulkan.vkCmdDraw(context.command_buffer, 3, 1, 0, 0);

    if (true) {
        cimgui.ImGui_ImplVulkan_RenderDrawData(cimgui.igGetDrawData(), @ptrCast(context.command_buffer), null);
    }
}
