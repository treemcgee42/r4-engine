const std = @import("std");
const Renderer = @import("./Renderer.zig");
const VulkanSwapchain = @import("vulkan//Swapchain.zig");
const Surface = @import("./Surface.zig");
const Window = @import("../Window.zig");
const CallbackHandle = @import("../Reactable.zig").CallbackHandle;

swapchain: VulkanSwapchain,
num_images: usize,

recreate_callback_data: *RecreateCallbackData,
recreate_callback_handle: CallbackHandle,

pub const max_frames_in_flight: usize = VulkanSwapchain.max_frames_in_flight;

const Swapchain = @This();

pub fn init(renderer: *Renderer, surface: *const Surface) !Swapchain {
    const swapchain = try VulkanSwapchain.init(
        renderer.allocator,
        &renderer.system,
        surface.surface,
    );

    const num_images = swapchain.swapchain_image_views.len;

    const callback_data = try renderer.allocator.create(RecreateCallbackData);

    return .{
        .swapchain = swapchain,
        .num_images = num_images,
        .recreate_callback_data = callback_data,
        .recreate_callback_handle = 0,
    };
}

pub fn register_recreate_callback_for_window_size(
    self: *Swapchain,
    renderer: *Renderer,
    window: *Window,
) !void {
    self.recreate_callback_data.* = .{
        .self = self,
        .renderer = renderer,
        .window = window,
    };

    const handle = try window.window_size_pixels.add_callback(.{
        .callback_fn = &recreate_callback,
        .extra_data = @ptrCast(self.recreate_callback_data),
        .priority = 100,
        .name = "Renderer::Swapchain",
    });
    self.recreate_callback_handle = handle;
}

const RecreateCallbackData = struct {
    self: *Swapchain,
    renderer: *Renderer,
    window: *Window,
};

pub fn recreate_callback(new_size: Window.WindowSize, data_untyped: ?*anyopaque) void {
    _ = new_size;
    const data: *RecreateCallbackData = @ptrCast(@alignCast(data_untyped.?));

    data.self.recreate(data.renderer, data.window) catch unreachable;
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

pub fn deinit(self: *Swapchain, renderer: *Renderer, window: *Window) void {
    window.window_size_pixels.remove_callback(self.recreate_callback_handle);
    renderer.allocator.destroy(self.recreate_callback_data);

    const deinit_ctx = renderer.system.allocator.create(VulkanSwapchain.DeinitGenericCtx) catch unreachable;
    deinit_ctx.* = VulkanSwapchain.DeinitGenericCtx{
        .swapchain = &self.swapchain,
        .system = &renderer.system,
    };

    renderer.system.deinit_queue.insert(
        @ptrCast(deinit_ctx),
        &VulkanSwapchain.deinit_generic,
    ) catch unreachable;
}
