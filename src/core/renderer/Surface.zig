const vulkan = @import("vulkan");
const glfw = @import("glfw");
const Renderer = @import("Renderer.zig");
const VulkanSystem = @import("./vulkan//VulkanSystem.zig");

surface: union {
    vulkan: vulkan.VkSurfaceKHR,
},

const Window = @This();

pub fn init(renderer: *Renderer, window: *glfw.GLFWwindow) !Window {
    const surface = switch (renderer.backend) {
        .vulkan => try VulkanSystem.create_surface(renderer.system.vulkan.instance, window),
    };

    return .{
        .surface = .{ .vulkan = surface },
    };
}

pub fn deinit(self: Window, renderer: *Renderer) void {
    switch (renderer.backend) {
        .vulkan => {
            vulkan.vkDestroySurfaceKHR(renderer.system.vulkan.instance, self.surface.vulkan, null);
        },
    }
}
