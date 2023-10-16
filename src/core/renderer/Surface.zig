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
    vulkan.vkDestroySurfaceKHR(renderer.system.instance, self.surface, null);
}
