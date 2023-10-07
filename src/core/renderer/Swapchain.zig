const std = @import("std");
const Context = @import("./Context.zig");
const VulkanSwapchain = @import("vulkan//Swapchain.zig");
const Surface = @import("./Surface.zig");
const Window = @import("../Window.zig");

swapchain: union {
    vulkan: VulkanSwapchain,
},
num_images: usize,

pub const max_frames_in_flight: usize = VulkanSwapchain.max_frames_in_flight;

const Swapchain = @This();

pub fn init(allocator: std.mem.Allocator, context: *Context, surface: *const Surface) !Swapchain {
    const swapchain = try switch (context.backend) {
        .vulkan => VulkanSwapchain.init(allocator, &context.system.vulkan, surface.surface.vulkan),
    };

    const num_images = switch (context.backend) {
        .vulkan => swapchain.swapchain_image_views.len,
    };

    return .{
        .swapchain = .{ .vulkan = swapchain },
        .num_images = num_images,
    };
}

pub fn recreate(self: *Swapchain, allocator: std.mem.Allocator, context: *Context, window: *Window) !void {
    switch (context.backend) {
        .vulkan => {
            const swapchain_settings = try VulkanSwapchain.query_swapchain_settings(
                allocator,
                context.system.vulkan.physical_device,
                context.system.vulkan.logical_device,
                window.surface.surface.vulkan,
            );
            try self.swapchain.vulkan.recreate_swapchain(allocator, &context.system.vulkan, swapchain_settings, window.window);
        },
    }
}

pub fn deinit(self: Swapchain, allocator: std.mem.Allocator, context: *Context) void {
    switch (context.backend) {
        .vulkan => {
            self.swapchain.vulkan.deinit(allocator, &context.system.vulkan);
        },
    }
}
