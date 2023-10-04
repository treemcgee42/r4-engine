const std = @import("std");
const glfw = @import("../c/glfw.zig");
const VulkanSystem = @import("vulkan/VulkanSystem.zig");

const Core = @This();

// gpa: std.heap.GeneralPurposeAllocator(.{}),
allocator: std.mem.Allocator,

vulkan_system: VulkanSystem,

pub const CoreInitError = error{
    glfw_init_failed,
    vulkan_init_failed,
};

pub fn init(allocator: std.mem.Allocator) CoreInitError!Core {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // errdefer _ = gpa.deinit();
    // const allocator = gpa.allocator();

    if (glfw.glfwInit() == 0) {
        return CoreInitError.glfw_init_failed;
    }

    var vulkan_system = VulkanSystem.init(allocator) catch {
        return CoreInitError.vulkan_init_failed;
    };

    return .{
        // .gpa = gpa,
        .allocator = allocator,

        .vulkan_system = vulkan_system,
    };
}

pub fn deinit(self: *Core) void {
    self.vulkan_system.deinit(self.allocator);
    // _ = self.gpa.deinit();
}
