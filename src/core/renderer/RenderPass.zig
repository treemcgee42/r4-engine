const std = @import("std");
const cimgui = @import("cimgui");
const vulkan = @import("vulkan");
const VulkanRenderPass = @import("vulkan//RenderPass.zig");
const Renderer = @import("./Renderer.zig");
const Swapchain = @import("./Swapchain.zig");
const Window = @import("../Window.zig");

enable_imgui: bool,
render_pass: union {
    vulkan: VulkanRenderPass,
},

const RenderPass = @This();

pub fn init(renderer: *Renderer, window: *Window) !RenderPass {
    var render_pass = try switch (renderer.backend) {
        .vulkan => VulkanRenderPass.init_basic_primary(.{
            .allocator = renderer.allocator,
            .system = &renderer.system.vulkan,
            .swapchain = &window.swapchain.swapchain.vulkan,
        }),
    };

    switch (renderer.backend) {
        .vulkan => {
            try render_pass.setup_imgui(&renderer.system.vulkan, window);
        },
    }

    return .{
        .enable_imgui = true,
        .render_pass = .{
            .vulkan = render_pass,
        },
    };
}

pub fn deinit(self: *RenderPass, renderer: *Renderer) void {
    switch (renderer.backend) {
        .vulkan => {
            self.render_pass.vulkan.deinit(renderer.allocator, &renderer.system.vulkan);
        },
    }
}

pub fn recreate_swapchain_callback(
    self: *RenderPass,
    renderer: *Renderer,
    swapchain: *Swapchain,
) !void {
    switch (renderer.backend) {
        .vulkan => {
            try self.render_pass.vulkan.recreate_swapchain_callback(renderer.allocator, &renderer.system.vulkan, &swapchain.swapchain.vulkan);
        },
    }
}

pub fn begin(self: *RenderPass, renderer: *Renderer, swapchain: *Swapchain) !void {
    self.render_pass.vulkan.begin(&swapchain.swapchain.vulkan, renderer.current_frame_context.?.command_buffer, renderer.current_frame_context.?.image_index);
}

pub fn end(self: *RenderPass, renderer: *Renderer) !void {
    const command_buffer = renderer.current_frame_context.?.command_buffer;

    self.render_pass.vulkan.end(command_buffer);
}
