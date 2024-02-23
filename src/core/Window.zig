const std = @import("std");
const vulkan = @import("vulkan");
const glfw = @import("glfw");
const cimgui = @import("cimgui");
const Core = @import("Core.zig");
const Swapchain = @import("renderer/vulkan/Swapchain.zig");
const RenderPass = @import("renderer/RenderPass.zig");
const Renderer = @import("renderer/Renderer.zig");
const Resource = Renderer.Resource;
const buffer = @import("renderer/vulkan//buffer.zig");
const VulkanSystem = @import("renderer/vulkan/VulkanSystem.zig");
const Scene = @import("renderer/Scene.zig");
const math = @import("math");
const gltf_loader = @import("renderer/gltf_loader/gltf_loader.zig");
const Reactable = @import("Reactable.zig").Reactable;

const Window = @This();

/// Window size in device-independent units.
window_size: Reactable(WindowSize),
/// Window size in pixels (accounts for DPI).
window_size_pixels: Reactable(WindowSize),

window: *glfw.GLFWwindow,
framebuffer_resized: bool = false,

pub const WindowInitInfo = struct {
    width: u32 = 800,
    height: u32 = 600,
    name: []const u8 = "Untitled Window",
};

pub const WindowInitError = error{
    glfw_init_failed,
    glfw_create_window_failed,
    surface_creation_failed,
    swapchain_creation_failed,
};

/// Note GLFW must be initialized beforehand, e.g. call `glfw.glfwInit()` before trying to
/// create a window
pub fn init(core: *Core, info: *const WindowInitInfo) WindowInitError!Window {
    // ---

    const size_ = Reactable(WindowSize).init_with_data(
        core.allocator,
        .{ .width = info.width, .height = info.height },
        "window size",
    );

    // ---

    glfw.glfwWindowHint(glfw.GLFW_CLIENT_API, glfw.GLFW_NO_API);
    glfw.glfwWindowHint(glfw.GLFW_RESIZABLE, glfw.GLFW_TRUE);

    const maybe_window = glfw.glfwCreateWindow(
        @intCast(info.width),
        @intCast(info.height),
        @ptrCast(info.name),
        null,
        null,
    );
    if (maybe_window == null) {
        return WindowInitError.glfw_create_window_failed;
    }

    // ---

    var pixel_width: c_int = 0;
    var pixel_height: c_int = 0;
    glfw.glfwGetFramebufferSize(maybe_window, &pixel_width, &pixel_height);
    const size_pixels = Reactable(WindowSize).init_with_data(
        core.allocator,
        .{
            .width = @intCast(pixel_width),
            .height = @intCast(pixel_height),
        },
        "window size pixels",
    );

    // ---

    core.renderer.system.init_swapchain(maybe_window.?) catch {
        return WindowInitError.swapchain_creation_failed;
    };

    // ---

    return .{
        .window_size = size_,
        .window_size_pixels = size_pixels,

        .window = maybe_window.?,
    };
}

pub fn should_close(self: *Window) bool {
    if (glfw.glfwWindowShouldClose(self.window) == 0) {
        glfw.glfwPollEvents();
        return false;
    }

    return true;
}

pub fn deinit(self: *Window, core: *Core) void {
    _ = core;
    self.window_size.deinit();
    self.window_size_pixels.deinit();

    glfw.glfwDestroyWindow(self.window);
}

pub fn setup_resize(self: *Window, renderer: *Renderer) !void {
    glfw.glfwSetWindowUserPointer(self.window, self);
    _ = glfw.glfwSetFramebufferSizeCallback(self.window, window_resize_callback);

    try renderer.system.swapchain.register_recreate_callback_for_window_size(renderer, self);
}

fn window_resize_callback(window: ?*glfw.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    var app: *Window = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(window)));
    app.framebuffer_resized = true;
    app.window_size.set(.{ .width = @intCast(width), .height = @intCast(height) });

    var pixels_width: c_int = 0;
    var pixels_height: c_int = 0;
    glfw.glfwGetFramebufferSize(window, &pixels_width, &pixels_height);
    app.window_size_pixels.set(.{ .width = @intCast(pixels_width), .height = @intCast(pixels_height) });
}

pub fn recreate_swapchain_callback(self: *Window, renderer: *Renderer) !void {
    try renderer.system.swapchain.recreate(renderer, self);
}

pub const WindowSize = struct {
    width: u32,
    height: u32,
};

/// Returns (width, height) for device-independent dimensions.
pub fn size(self: *const Window) WindowSize {
    return .{
        .width = self.window_size.data.width,
        .height = self.window_size.data.height,
    };
}

pub fn get_size_pixels(self: *const Window) WindowSize {
    return .{
        .width = self.window_size_pixels.data.width,
        .height = self.window_size_pixels.data.height,
    };
}
