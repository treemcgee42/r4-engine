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
const buffer = @import("renderer/vulkan//buffer.zig");
const VulkanSystem = @import("renderer/vulkan/VulkanSystem.zig");
const Scene = @import("renderer/Scene.zig");
const math = @import("math");
const gltf_loader = @import("renderer/gltf_loader/gltf_loader.zig");

const Window = @This();

window: *glfw.GLFWwindow,
surface: Surface,
framebuffer_resized: bool = false,

swapchain: Swapchain,

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

    // ---

    return .{
        .window = maybe_window.?,
        .surface = surface,

        .swapchain = swapchain,

        .imgui_enabled = false,
    };
}

pub fn should_close(self: *Window) bool {
    if (glfw.glfwWindowShouldClose(self.window) == 0) {
        glfw.glfwPollEvents();
        return false;
    }

    return true;
}

pub fn run_main_loop(self: *Window, core: *Core) !void {
    try core.renderer.enable_ui(self, .{ .docking_enabled = true });
    const window_size = self.size();

    // --- Scene pass, rendering to image.
    const scene_pass_render_target = try core.renderer.resource_system.create_resource(.{
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
        .depth_test = true,
        .name = "Scene Pass",
    };
    const scene_pass = try core.renderer.create_renderpass(&scene_pass_info);
    const scene_pipeline = try core.renderer.create_pipeline(.{
        .name = "Hello Triangle",
        .vertex_shader_filename = "shaders/compiled_output/tri_mesh.vert.spv",
        .fragment_shader_filename = "shaders/compiled_output/tri_mesh.frag.spv",
        .front_face_orientation = .counter_clockwise,
        .topology = .triangle_list,
        .depth_test_enabled = true,
        .render_pass = scene_pass,
    });

    // ---

    var scene = try core.allocator.create(Scene);
    scene.* = try Scene.init(core.allocator, &core.renderer);
    try core.renderer.system.deinit_queue.insert(
        @ptrCast(scene),
        Scene.deinit_generic,
    );

    const material_handle = try scene.material_system.register_material(Scene.Material{
        .pipeline = scene_pipeline,
    });

    var tri_verts = [_]Scene.Vertex{ .{
        .position = math.Vec3f.init(0.0, -0.5, 0.0),
        .normal = math.Vec3f.init(0, 0, 1),
        .color = math.Vec3f.init(1, 0, 0),
    }, .{
        .position = math.Vec3f.init(0.5, 0.5, 0.0),
        .normal = math.Vec3f.init(0, 0, 1),
        .color = math.Vec3f.init(0, 1, 0),
    }, .{
        .position = math.Vec3f.init(-0.5, 0.5, 0.0),
        .normal = math.Vec3f.init(0, 0, 1),
        .color = math.Vec3f.init(0, 0, 1),
    } };
    const tri_mesh = try scene.mesh_system.register("triangle", &tri_verts);
    const tri_scene_obj = try scene.create_object("triangle");
    try scene.assign_mesh_to_object(tri_scene_obj, tri_mesh);
    try scene.assign_material_to_object(tri_scene_obj, material_handle);

    const cube_verts = try gltf_loader.load_from_file(&core.allocator, "models/Box.glb");
    defer core.allocator.free(cube_verts);
    const cube_mesh = try scene.mesh_system.register("cube", cube_verts);
    const cube_scene_obj = try scene.create_object("cube");
    try scene.assign_mesh_to_object(cube_scene_obj, cube_mesh);
    try scene.assign_material_to_object(cube_scene_obj, material_handle);

    const duck_verts = try gltf_loader.load_from_file(&core.allocator, "models/Duck.glb");
    defer core.allocator.free(duck_verts);
    const duck_mesh = try scene.mesh_system.register("duck", duck_verts);
    const duck_scene_obj = try scene.create_object("duck");
    try scene.assign_mesh_to_object(duck_scene_obj, duck_mesh);
    try scene.assign_material_to_object(duck_scene_obj, material_handle);

    // --- Main pass.
    const main_pass_render_target = try core.renderer.resource_system.create_resource(.{
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
    _ = pipeline;

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
    var background_color: [3]f32 = .{ 0.1, 0.1, 0.1 };
    var selected_scene_object_idx: ?usize = null;

    while (glfw.glfwWindowShouldClose(self.window) == 0) {
        glfw.glfwPollEvents();

        // ---

        core.renderer.begin_imgui();

        core.renderer.ui.?.create_full_window_dock_space();

        {
            _ = cimgui.igBegin("Left panel", &left_panel_open, 0);

            var i: usize = 0;
            while (i < scene.objects.items.len) : (i += 1) {
                const object = scene.objects.items[i];
                if (cimgui.igSelectable_Bool(
                    object.name,
                    selected_scene_object_idx == i,
                    0,
                    cimgui.ImVec2{ .x = 0, .y = 0 },
                )) {
                    if (selected_scene_object_idx == i) {
                        // If already selected, deselect.
                        selected_scene_object_idx = null;
                    } else {
                        selected_scene_object_idx = i;
                    }
                }
            }

            cimgui.igEnd();
        }

        {
            _ = cimgui.igBegin("Bottom panel", &right_panel_open, 0);

            if (selected_scene_object_idx == null) {
                // Scene settings.
                cimgui.igText("Scene settings");
                // Background color
                _ = cimgui.igColorEdit3("Background color", &background_color, 0);
                core.renderer.set_renderpass_clear_color(
                    scene_pass,
                    .{
                        background_color[0],
                        background_color[1],
                        background_color[2],
                        1.0,
                    },
                );
            } else {
                // Object settings.
                const object = scene.objects.items[selected_scene_object_idx.?];
                cimgui.igText(object.name);

                // Translation
                const object_translation_ptr = scene.objects_ecs.get_component_for_entity(
                    object.entity,
                    Scene.Translation,
                ).?;
                var editable_translation = [3]f32{
                    object_translation_ptr.val.raw[0],
                    object_translation_ptr.val.raw[1],
                    object_translation_ptr.val.raw[2],
                };
                _ = cimgui.igDragFloat3(
                    "Translation",
                    &editable_translation,
                    0.1,
                    0,
                    0,
                    "%.2f",
                    0,
                );
                if (editable_translation[0] != object_translation_ptr.val.raw[0] or
                    editable_translation[1] != object_translation_ptr.val.raw[1] or
                    editable_translation[2] != object_translation_ptr.val.raw[2])
                {
                    const new_translation = Scene.Translation{
                        .val = math.Vec3f.init(
                            editable_translation[0],
                            editable_translation[1],
                            editable_translation[2],
                        ),
                    };
                    try scene.update_translation_of_object(object.entity, new_translation);
                }

                // Scale
                const object_scale_ptr = scene.objects_ecs.get_component_for_entity(
                    object.entity,
                    Scene.Scale,
                ).?;
                var editable_scale = [3]f32{
                    object_scale_ptr.val.raw[0],
                    object_scale_ptr.val.raw[1],
                    object_scale_ptr.val.raw[2],
                };
                _ = cimgui.igDragFloat3(
                    "Scale",
                    &editable_scale,
                    0.1,
                    0,
                    0,
                    "%.2f",
                    0,
                );
                if (editable_scale[0] != object_scale_ptr.val.raw[0] or
                    editable_scale[1] != object_scale_ptr.val.raw[1] or
                    editable_scale[2] != object_scale_ptr.val.raw[2])
                {
                    const new_scale = Scene.Scale{
                        .val = math.Vec3f.init(
                            editable_scale[0],
                            editable_scale[1],
                            editable_scale[2],
                        ),
                    };
                    try scene.update_scale_of_object(object.entity, new_scale);
                }
            }

            cimgui.igEnd();
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
        try scene.draw();
        try core.renderer.end_renderpass(scene_pass);

        try core.renderer.begin_renderpass(render_pass);

        // try core.renderer.bind_pipeline(pipeline);
        // try core.renderer.draw(3);

        try core.renderer.end_renderpass(render_pass);

        try core.renderer.end_frame(self);
    }
}

pub fn deinit(self: *Window, core: *Core) void {
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
