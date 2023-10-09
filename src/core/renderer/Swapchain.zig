const std = @import("std");
const Renderer = @import("./Renderer.zig");
const VulkanSwapchain = @import("vulkan//Swapchain.zig");
const Surface = @import("./Surface.zig");
const Window = @import("../Window.zig");

swapchain: union {
    vulkan: VulkanSwapchain,
},
num_images: usize,

pub const max_frames_in_flight: usize = VulkanSwapchain.max_frames_in_flight;

const Swapchain = @This();

pub fn init(renderer: *Renderer, surface: *const Surface) !Swapchain {
    const swapchain = try switch (renderer.backend) {
        .vulkan => VulkanSwapchain.init(renderer.allocator, &renderer.system.vulkan, surface.surface.vulkan),
    };

    const num_images = switch (renderer.backend) {
        .vulkan => swapchain.swapchain_image_views.len,
    };

    return .{
        .swapchain = .{ .vulkan = swapchain },
        .num_images = num_images,
    };
}

pub fn recreate(self: *Swapchain, renderer: *Renderer, window: *Window) !void {
    switch (renderer.backend) {
        .vulkan => {
            const swapchain_settings = try VulkanSwapchain.query_swapchain_settings(
                renderer.allocator,
                renderer.system.vulkan.physical_device,
                renderer.system.vulkan.logical_device,
                window.surface.surface.vulkan,
            );
            try self.swapchain.vulkan.recreate_swapchain(renderer.allocator, &renderer.system.vulkan, swapchain_settings, window.window);
        },
    }
}

pub fn deinit(self: Swapchain, renderer: *Renderer) void {
    switch (renderer.backend) {
        .vulkan => {
            self.swapchain.vulkan.deinit(renderer.allocator, &renderer.system.vulkan);
        },
    }
}
