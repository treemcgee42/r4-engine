const std = @import("std");
const Renderer = @import("./Renderer.zig");
const VulkanSwapchain = @import("vulkan//Swapchain.zig");
const Surface = @import("./Surface.zig");
const Window = @import("../Window.zig");

swapchain: VulkanSwapchain,
num_images: usize,

pub const max_frames_in_flight: usize = VulkanSwapchain.max_frames_in_flight;

const Swapchain = @This();

pub fn init(renderer: *Renderer, surface: *const Surface) !Swapchain {
    const swapchain = try VulkanSwapchain.init(
        renderer.allocator,
        &renderer.system,
        surface.surface,
    );

    const num_images = swapchain.swapchain_image_views.len;

    return .{
        .swapchain = swapchain,
        .num_images = num_images,
    };
}

pub fn recreate(self: *Swapchain, renderer: *Renderer, window: *Window) !void {
    const swapchain_settings = try VulkanSwapchain.query_swapchain_settings(
        renderer.allocator,
        renderer.system.physical_device,
        renderer.system.logical_device,
        window.surface.surface,
    );
    try self.swapchain.recreate_swapchain(
        renderer.allocator,
        &renderer.system,
        swapchain_settings,
        window.window,
    );
}

pub fn deinit(self: Swapchain, renderer: *Renderer) void {
    self.swapchain.deinit(renderer.allocator, &renderer.system);
}
