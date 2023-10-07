const vulkan = @import("vulkan");
const glfw = @import("glfw");
const Context = @import("./Context.zig");
const VulkanSystem = @import("./vulkan//VulkanSystem.zig");

surface: union {
    vulkan: vulkan.VkSurfaceKHR,
},

const Window = @This();

pub fn init(context: *Context, window: *glfw.GLFWwindow) !Window {
    const surface = switch (context.backend) {
        .vulkan => try VulkanSystem.create_surface(context.system.vulkan.instance, window),
    };

    return .{
        .surface = .{ .vulkan = surface },
    };
}

pub fn deinit(self: Window, context: *Context) void {
    switch (context.backend) {
        .vulkan => {
            vulkan.vkDestroySurfaceKHR(context.system.vulkan.instance, self.surface.vulkan, null);
        },
    }
}
