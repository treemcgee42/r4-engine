const std = @import("std");
const glfw = @import("glfw");
const RendererContext = @import("renderer/Context.zig");

const Core = @This();

// gpa: std.heap.GeneralPurposeAllocator(.{}),
allocator: std.mem.Allocator,

renderer_context: RendererContext,

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

    var renderer_context = RendererContext.init(allocator, .vulkan) catch {
        return CoreInitError.vulkan_init_failed;
    };

    return .{
        // .gpa = gpa,
        .allocator = allocator,

        .renderer_context = renderer_context,
    };
}

pub fn deinit(self: *Core) void {
    self.renderer_context.system.vulkan.deinit(self.allocator);
    // _ = self.gpa.deinit();
}
