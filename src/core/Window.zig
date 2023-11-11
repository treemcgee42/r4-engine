const std = @import("std");
const vulkan = @import("vulkan");
const glfw = @import("glfw");
const cimgui = @import("cimgui");
const Core = @import("Core.zig");
const Surface = @import("renderer/Surface.zig");
const Swapchain = @import("renderer/Swapchain.zig");
const RenderPass = @import("renderer/RenderPass.zig");
const Renderer = @import("renderer/Renderer.zig");
const Resource = Renderer.Resource;

const Window = @This();

window: *glfw.GLFWwindow,
surface: Surface,
framebuffer_resized: bool,

swapchain: Swapchain,

render_passes: std.ArrayList(RenderPass),

imgui_enabled: bool,
imgui_descriptor_pool: vulkan.VkDescriptorPool = null,

show_imgui_demo_window: bool = true,

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

    const surface = Surface.init(&core.renderer, maybe_window.?) catch {
        return WindowInitError.surface_creation_failed;
    };

    // ---

    const swapchain = Swapchain.init(&core.renderer, &surface) catch {
        return WindowInitError.swapchain_creation_failed;
    };

    const render_passes = std.ArrayList(RenderPass).init(core.allocator);

    // ---

    return .{
        .window = maybe_window.?,
        .surface = surface,
        .framebuffer_resized = false,

        .swapchain = swapchain,

        .render_passes = render_passes,

        .imgui_enabled = false,
    };
}

pub fn run_main_loop(self: *Window, core: *Core) !void {
    try core.renderer.enable_ui(self, .{ .docking_enabled = true });
    const window_size = self.size();

    // --- Scene pass, rendering to image.
    var scene_pass_render_target = try core.renderer.resource_system.create_resource(.{
        .kind = .color_texture,
        .width = window_size.width,
        .height = window_size.height,
    });
    var scene_pass_productions = [_]Resource{scene_pass_render_target};
    var scene_pass_info = Renderer.RenderPassInfo{
        .enable_imgui = false,
        .renderer = &core.renderer,
        .window = self,
        .tag = .render_to_image,
        .produces = &scene_pass_productions,
        .depends_on = &[_]Resource{},
        .name = "Scene Pass",
    };
    const scene_pass = try core.renderer.create_renderpass(&scene_pass_info);
    const scene_pipeline = try core.renderer.create_pipeline(.{
        .name = "Hello Triangle",
        .vertex_shader_filename = "shaders/compiled_output/triangle.vert.spv",
        .fragment_shader_filename = "shaders/compiled_output/triangle.frag.spv",
        .front_face_orientation = .clockwise,
        .topology = .triangle_list,
        .render_pass = scene_pass,
    });

    // --- Main pass.
    var main_pass_render_target = try core.renderer.resource_system.create_resource(.{
        .kind = .final_texture,
        .width = window_size.width,
        .height = window_size.height,
    });
    var main_pass_productions = [_]Resource{
        main_pass_render_target,
    };
    var main_pass_dependencies = [_]Resource{
        scene_pass_productions[0],
    };
    var render_pass_info = Renderer.RenderPassInfo{
        .enable_imgui = false,
        .renderer = &core.renderer,
        .window = self,
        .tag = .basic_primary,
        .produces = &main_pass_productions,
        .depends_on = &main_pass_dependencies,
        .name = "Main Pass",
    };
    const render_pass = try core.renderer.create_renderpass(&render_pass_info);
    const pipeline = try core.renderer.create_pipeline(.{
        .name = "Hello Triangle",
        .vertex_shader_filename = "shaders/compiled_output/triangle.vert.spv",
        .fragment_shader_filename = "shaders/compiled_output/triangle.frag.spv",
        .front_face_orientation = .clockwise,
        .topology = .triangle_list,
        .render_pass = render_pass,
    });

    // --- State
    var viewport_open = true;
    var viewport_size: cimgui.ImVec2 = undefined;
    var new_viewport_size_a: cimgui.ImVec2 = undefined;
    var new_viewport_size_b: cimgui.ImVec2 = undefined;
    var new_viewport_size: cimgui.ImVec2 = undefined;
    // var viewport_size_string_buffer: [256]u8 = undefined;
    // var viewport_size_string: []u8 = undefined;
    var left_panel_open = true;
    var right_panel_open = true;

    while (glfw.glfwWindowShouldClose(self.window) == 0) {
        glfw.glfwPollEvents();

        // ---

        core.renderer.begin_imgui();

        core.renderer.ui.?.create_full_window_dock_space();

        {
            _ = cimgui.igBegin("Left panel", &left_panel_open, 0);
        }

        {
            _ = cimgui.igBegin("Bottom panel", &right_panel_open, 0);
        }

        // cimgui.igShowDemoWindow(&self.show_imgui_demo_window);

        {
            _ = cimgui.igBegin("Viewport", &viewport_open, 0);
            cimgui.igGetWindowSize(&viewport_size);
            cimgui.igGetWindowContentRegionMin(&new_viewport_size_a);
            cimgui.igGetWindowContentRegionMax(&new_viewport_size_b);
            new_viewport_size = cimgui.ImVec2{
                .x = new_viewport_size_b.x - new_viewport_size_a.x,
                .y = new_viewport_size_b.y - new_viewport_size_a.y,
            };

            core.renderer.ui.?.display_image_as_resource(new_viewport_size);

            cimgui.igEnd();
        }

        core.renderer.end_imgui();

        // ---

        try core.renderer.begin_frame(self);

        try core.renderer.begin_renderpass(scene_pass);
        try core.renderer.bind_pipeline(scene_pipeline);
        try core.renderer.draw(3);
        try core.renderer.end_renderpass(scene_pass);

        try core.renderer.begin_renderpass(render_pass);

        try core.renderer.bind_pipeline(pipeline);
        try core.renderer.draw(3);

        try core.renderer.end_renderpass(render_pass);

        try core.renderer.end_frame(self);
        // @panic("planned");
    }
}

pub fn deinit(self: *Window, core: *Core) void {
    var i: usize = 0;
    while (i < self.render_passes.items.len) : (i += 1) {
        self.render_passes.items[i].deinit(&core.renderer);
    }
    self.render_passes.deinit();

    self.swapchain.deinit(&core.renderer);

    self.surface.deinit(&core.renderer);
    glfw.glfwDestroyWindow(self.window);
}

pub fn add_renderpass(self: *Window, render_pass: RenderPass) void {
    self.render_passes.append(render_pass) catch unreachable;
}

pub fn setup_resize(self: *Window) void {
    glfw.glfwSetWindowUserPointer(self.window, self);
    _ = glfw.glfwSetFramebufferSizeCallback(self.window, window_resize_callback);
}

fn window_resize_callback(window: ?*glfw.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    _ = height;
    _ = width;
    var app: *Window = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(window)));
    app.framebuffer_resized = true;
}

pub fn recreate_swapchain_callback(self: *Window, renderer: *Renderer) !void {
    try self.swapchain.recreate(renderer, self);

    try renderer.system.handle_swapchain_resize_for_renderpasses(self);
}

pub const WindowSize = struct {
    width: u32,
    height: u32,
};

/// Returns (width, height).
pub fn size(self: *const Window) WindowSize {
    return .{
        .width = self.swapchain.swapchain.swapchain_extent.width,
        .height = self.swapchain.swapchain.swapchain_extent.height,
    };
}
