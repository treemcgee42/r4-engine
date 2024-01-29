const std = @import("std");
const Renderer = @import("./Renderer.zig");
const VulkanSwapchain = @import("vulkan//Swapchain.zig");
const Surface = @import("./Surface.zig");
const Window = @import("../Window.zig");

swapchain_ptr: *VulkanSwapchain,
num_images: usize,

pub const max_frames_in_flight: usize = VulkanSwapchain.max_frames_in_flight;

const Swapchain = @This();

pub fn init(renderer: *Renderer, surface: *const Surface) !Swapchain {
    try renderer.system.init_swapchain(surface.surface);
    const swapchain_ptr = &renderer.system.swapchain.?;

    const num_images = swapchain_ptr.swapchain_image_views.len;

    return .{
        .swapchain_ptr = swapchain_ptr,
        .num_images = num_images,
    };
}

pub fn recreate(self: *Swapchain, renderer: *Renderer, window: *Window) !void {
    _ = self;
    try renderer.system.recreate_swapchain(window.window, window.surface.surface);
}

pub fn deinit(self: Swapchain, renderer: *Renderer) void {
    self.swapchain_ptr.deinit(renderer.allocator, &renderer.system);
}
