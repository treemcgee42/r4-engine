const vulkan = @import("vulkan");
const glfw = @import("glfw");
const Renderer = @import("Renderer.zig");
const VulkanSystem = @import("./vulkan//VulkanSystem.zig");

surface: vulkan.VkSurfaceKHR,

const Window = @This();

pub fn init(renderer: *Renderer, window: *glfw.GLFWwindow) !Window {
    const surface = try VulkanSystem.create_surface(renderer.system.instance, window);

    return .{
        .surface = surface,
    };
}

pub fn deinit(self: Window, renderer: *Renderer) void {
    const ctx = renderer.system.allocator.create(DeinitCtx) catch unreachable;
    ctx.* = .{
        .system = &renderer.system,
        .surface = self.surface,
    };

    renderer.system.deinit_queue.insert(
        @ptrCast(ctx),
        &deinit_generic,
    ) catch unreachable;
}

const DeinitCtx = struct {
    system: *VulkanSystem,
    surface: vulkan.VkSurfaceKHR,
};

fn deinit_generic(ctx_untyped: *anyopaque) void {
    const ctx: *DeinitCtx = @ptrCast(@alignCast(ctx_untyped));
    vulkan.vkDestroySurfaceKHR(ctx.system.instance, ctx.surface, null);

    ctx.system.allocator.destroy(ctx);
}
