// Demonstrates rendering the triangle to an offscreen attachment and then
// displaying it as an ImGui texture, like a viewport in an editor.

const std = @import("std");

const r4_core = @import("r4_core");
const math = r4_core.math;
const gltf_loader = r4_core.gltf_loader;
const vulkan = r4_core.vulkan;
const cimgui = r4_core.cimgui;
const l0vk = r4_core.l0vk;
const Core = r4_core.Core;
const Window = r4_core.Window;
const Scene = r4_core.Scene;

const rendergraph = r4_core.rendergraph;
const Rendergraph = rendergraph.RenderGraph;
const ResourceDescription = r4_core.rendergraph.ResourceDescription;

pub const ScenePass = struct {
    core: *Core,
    window: *Window,
    pipeline: l0vk.VkPipeline,
    pipeline_layout: l0vk.VkPipelineLayout,
    scene: *Scene,

    pub fn init(core: *Core, window: *Window) !ScenePass {
        var push_constant_ranges = [_]l0vk.VkPushConstantRange{.{
            .offset = 0,
            .size = @sizeOf(Scene.PushConstants),
            .stageFlags = .{
                .vertex = true,
            },
        }};
        var binding_descriptions = [_]l0vk.VkVertexInputBindingDescription{
            core.renderer.system.get_binding_description(Scene.Vertex),
        };
        const attribute_descriptions = try core.renderer.system.get_attribute_descriptions(
            core.allocator,
            Scene.Vertex,
        );
        defer core.allocator.free(attribute_descriptions);

        const pipeline_create_info = r4_core.pipeline.PipelineCreateInfo{
            .vertex_shader_filename = "shaders/compiled_output/tri_mesh.vert.spv",
            .fragment_shader_filename = "shaders/compiled_output/tri_mesh.frag.spv",
            .renderpass_name = "scene",
            .push_constant_ranges = &push_constant_ranges,
            .vertex_binding_descriptions = &binding_descriptions,
            .attribute_descriptions = attribute_descriptions,
            .depth_test_enabled = true,
        };
        const pipeline_and_layout = try core.renderer.system.pipeline_system.create(
            &core.renderer.system,
            "scene pass pipeline",
            pipeline_create_info,
        );

        // ---

        var scene = try core.allocator.create(Scene);
        scene.* = try Scene.init(core.allocator, &core.renderer);
        try core.renderer.system.deinit_queue.insert(
            @ptrCast(scene),
            Scene.deinit_generic,
        );

        const material_handle = try scene.material_system.register_material(Scene.Material{
            .pipeline = pipeline_and_layout.pipeline,
            .pipeline_layout = pipeline_and_layout.pipeline_layout,
        });

        // --- Scene objects

        // ------ Triangle

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

        // ------ Cube

        const cube_verts = try gltf_loader.load_from_file(
            &core.allocator,
            "models/Box.glb",
        );
        defer core.allocator.free(cube_verts);
        const cube_mesh = try scene.mesh_system.register("cube", cube_verts);
        const cube_scene_obj = try scene.create_object("cube");
        try scene.assign_mesh_to_object(cube_scene_obj, cube_mesh);
        try scene.assign_material_to_object(cube_scene_obj, material_handle);

        // ------ Duck

        const duck_verts = try gltf_loader.load_from_file(
            &core.allocator,
            "models/Duck.glb",
        );
        defer core.allocator.free(duck_verts);
        const duck_mesh = try scene.mesh_system.register("duck", duck_verts);
        const duck_scene_obj = try scene.create_object("duck");
        try scene.assign_mesh_to_object(duck_scene_obj, duck_mesh);
        try scene.assign_material_to_object(duck_scene_obj, material_handle);

        // ---

        return ScenePass{
            .core = core,
            .window = window,
            .pipeline = pipeline_and_layout.pipeline,
            .pipeline_layout = pipeline_and_layout.pipeline_layout,
            .scene = scene,
        };
    }

    pub fn render(self_untyped: *anyopaque, command_buffer: l0vk.VkCommandBuffer) anyerror!void {
        const self: *ScenePass = @ptrCast(@alignCast(self_untyped));

        vulkan.vkCmdBindPipeline(
            command_buffer,
            vulkan.VK_PIPELINE_BIND_POINT_GRAPHICS,
            self.pipeline,
        );

        const swapchain_extent = self.core.renderer.system.swapchain.swapchain_extent;

        const viewport = vulkan.VkViewport{
            .x = 0.0,
            .y = 0.0,
            .width = @floatFromInt(swapchain_extent.width),
            .height = @floatFromInt(swapchain_extent.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        vulkan.vkCmdSetViewport(command_buffer, 0, 1, &viewport);

        const scissor = vulkan.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = swapchain_extent,
        };
        vulkan.vkCmdSetScissor(command_buffer, 0, 1, &scissor);

        try self.scene.draw(command_buffer);
    }
};

pub const MainPass = struct {
    core: *Core,
    window: *Window,

    pub fn init(core: *Core, window: *Window) !MainPass {
        return MainPass{
            .core = core,
            .window = window,
        };
    }

    pub fn render(self_untyped: *anyopaque, command_buffer: l0vk.VkCommandBuffer) anyerror!void {
        const self: *MainPass = @ptrCast(@alignCast(self_untyped));

        const swapchain_extent = self.core.renderer.system.swapchain.swapchain_extent;

        const viewport = vulkan.VkViewport{
            .x = 0.0,
            .y = 0.0,
            .width = @floatFromInt(swapchain_extent.width),
            .height = @floatFromInt(swapchain_extent.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        vulkan.vkCmdSetViewport(command_buffer, 0, 1, &viewport);

        const scissor = vulkan.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = swapchain_extent,
        };
        vulkan.vkCmdSetScissor(command_buffer, 0, 1, &scissor);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .stack_trace_frames = 30,
    }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var core = try Core.init(allocator);
    defer core.deinit();

    var window_init_info = Window.WindowInitInfo{};
    window_init_info.name = "hello triangle";
    var window = try Window.init(&core, &window_init_info);
    defer window.deinit(&core);
    try window.setup_resize(&core.renderer);

    // ---

    var scene_pass: ScenePass = undefined;
    var main_pass: MainPass = undefined;

    // --- Build rendergraph.

    const swapchain_image_format = core.renderer.system.swapchain.swapchain_image_format;

    // ------ Scene node

    const scene_color_attachment = ResourceDescription{
        .name = "scene color",
        .kind = .attachment,
        .info = .{
            .attachment = .{
                .kind = .color,
                .format = swapchain_image_format,
                .resolution = .{
                    .relative = .{
                        .relative_to = .window,
                        .width_scale = 1.0,
                        .height_scale = 1.0,
                    },
                },
            },
        },
    };

    const scene_depth_attachment = ResourceDescription{
        .name = "scene depth",
        .kind = .attachment,
        .info = .{
            .attachment = .{
                .kind = .depth,
                .format = .d32_sfloat,
                .resolution = .{
                    .relative = .{
                        .relative_to = .window,
                        .width_scale = 1.0,
                        .height_scale = 1.0,
                    },
                },
            },
        },
    };

    var scene_inputs = std.ArrayList(ResourceDescription).init(core.allocator);
    defer scene_inputs.deinit();
    var scene_outputs = std.ArrayList(ResourceDescription).init(core.allocator);
    defer scene_outputs.deinit();
    try scene_outputs.append(scene_color_attachment);
    try scene_outputs.append(scene_depth_attachment);

    const scene_node = rendergraph.Node{
        .name = "scene",
        .inputs = scene_inputs,
        .outputs = scene_outputs,
        .render_fn = .{
            .function = &ScenePass.render,
            .data = &scene_pass,
        },
        .clear_color = .{ 0, 0, 0, 1 },
    };

    // ------ Final node

    const final_attachment = ResourceDescription{
        .name = "final",
        .kind = .attachment,
        .info = .{
            .attachment = .{
                .kind = .color_final,
                .format = swapchain_image_format,
                .resolution = .{
                    .relative = .{
                        .relative_to = .window,
                        .width_scale = 1.0,
                        .height_scale = 1.0,
                    },
                },
            },
        },
    };

    var inputs = std.ArrayList(ResourceDescription).init(core.allocator);
    defer inputs.deinit();
    try inputs.append(scene_color_attachment);
    var outputs = std.ArrayList(ResourceDescription).init(core.allocator);
    defer outputs.deinit();
    try outputs.append(final_attachment);

    const node = rendergraph.Node{
        .name = "main",
        .inputs = inputs,
        .outputs = outputs,
        .render_fn = .{
            .function = &MainPass.render,
            .data = &main_pass,
        },
        .clear_color = .{ 0.0, 0.5, 0.5, 1.0 },
        .imgui_enabled = true,
    };

    // ---

    var nodes = [_]rendergraph.Node{ scene_node, node };
    var rg = Rendergraph.init_empty(core.allocator);
    defer rg.deinit();
    try rg.set_nodes_from_slice(&nodes);
    try rg.compile(&core.renderer.system, &core.renderer, &window);
    std.debug.print("{}\n", .{rg});

    scene_pass = try ScenePass.init(&core, &window);
    main_pass = try MainPass.init(&core, &window);

    // --- ImGui state

    const sampler = try core.renderer.system.resource_system.get_image_sampler("scene color");
    const view = try core.renderer.system.resource_system.get_image_view("scene color");
    const imgui_image = try core.allocator.create(ImGuiSceneTextureData);
    defer core.allocator.destroy(imgui_image);
    imgui_image.* = .{
        .descriptor_set = @ptrCast(cimgui.ImGui_ImplVulkan_AddTexture(
            @ptrCast(sampler),
            @ptrCast(view),
            vulkan.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        )),
        .core = &core,
    };
    _ = try window.window_size_pixels.add_callback(.{
        .extra_data = @ptrCast(imgui_image),
        .callback_fn = &imGuiSceneTextureCallback,
        .name = "imgui scene texture",
    });

    var viewport_open = true;
    var viewport_size: cimgui.ImVec2 = undefined;
    var new_viewport_size_a: cimgui.ImVec2 = undefined;
    var new_viewport_size_b: cimgui.ImVec2 = undefined;
    var new_viewport_size: cimgui.ImVec2 = undefined;
    var left_panel_open = true;
    var right_panel_open = true;
    var background_color: [3]f32 = .{ 0.1, 0.1, 0.1 };
    var selected_scene_object_idx: ?usize = null;

    // --- Loop

    while (!window.should_close()) {
        cimgui.ImGui_ImplVulkan_NewFrame();
        cimgui.ImGui_ImplGlfw_NewFrame();
        cimgui.igNewFrame();

        create_full_window_dock_space();

        var scene = scene_pass.scene;

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
                // TODO
                _ = cimgui.igColorEdit3("Background color", &background_color, 0);
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
                    try scene_pass.scene.update_translation_of_object(object.entity, new_translation);
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

        {
            _ = cimgui.igBegin("Viewport", &viewport_open, 0);
            cimgui.igGetWindowSize(&viewport_size);
            cimgui.igGetWindowContentRegionMin(&new_viewport_size_a);
            cimgui.igGetWindowContentRegionMax(&new_viewport_size_b);
            new_viewport_size = cimgui.ImVec2{
                .x = new_viewport_size_b.x - new_viewport_size_a.x,
                .y = new_viewport_size_b.y - new_viewport_size_a.y,
            };

            cimgui.igImage(
                @ptrCast(imgui_image.descriptor_set),
                new_viewport_size,
                cimgui.ImVec2{ // default uv0
                    .x = 0,
                    .y = 0,
                },
                cimgui.ImVec2{ // default uv1
                    .x = 1,
                    .y = 1,
                },
                cimgui.ImVec4{ // default tint
                    .x = 1,
                    .y = 1,
                    .z = 1,
                    .w = 1,
                },
                cimgui.ImVec4{ // default border
                    .x = 0,
                    .y = 0,
                    .z = 0,
                    .w = 0,
                },
            );

            cimgui.igEnd();
        }

        cimgui.igRender();

        // ---

        try rg.execute(&core.renderer, &window);
    }
}

pub const ImGuiWindowFlags = packed struct(c_int) {
    no_title_bar: bool = false,
    no_resize: bool = false,
    no_move: bool = false,
    no_scrollbar: bool = false,

    no_scroll_with_mouse: bool = false,
    no_collapse: bool = false,
    always_auto_resize: bool = false,
    no_background: bool = false,

    no_saved_settings: bool = false,
    no_mouse_inputs: bool = false,
    menu_bar: bool = false,
    horizontal_scrollbar: bool = false,

    no_focus_on_appearing: bool = false,
    no_bring_to_front_on_focus: bool = false,
    always_vertical_scrollbar: bool = false,
    always_horizontal_scrollbar: bool = false,

    no_nav_inputs: bool = false,
    no_nav_focus: bool = false,
    unsaved_document: bool = false,
    no_docking: bool = false,

    _: u12 = 0,

    pub fn no_nav() ImGuiWindowFlags {
        return .{
            .no_nav_inputs = true,
            .no_nav_focus = true,
        };
    }

    pub fn no_decoration() ImGuiWindowFlags {
        return .{
            .no_title_bar = true,
            .no_resize = true,
            .no_move = true,
            .no_collapse = true,
        };
    }

    pub fn no_inputs() ImGuiWindowFlags {
        return .{
            .no_mouse_inputs = true,
            .no_nav_inputs = true,
            .no_nav_focus = true,
        };
    }
};

pub fn create_full_window_dock_space() void {
    // --- Create a fullscreen window.

    const viewport = cimgui.igGetMainViewport();
    cimgui.igSetNextWindowPos(viewport.*.WorkPos, 0, .{ .x = 0, .y = 0 });
    cimgui.igSetNextWindowSize(viewport.*.WorkSize, 0);
    cimgui.igSetNextWindowViewport(viewport.*.ID);
    cimgui.igPushStyleVar_Float(cimgui.ImGuiStyleVar_WindowRounding, 0.0);
    cimgui.igPushStyleVar_Float(cimgui.ImGuiStyleVar_WindowBorderSize, 0.0);
    const window_flags = ImGuiWindowFlags{
        .menu_bar = true,
        .no_docking = true,
        .no_title_bar = true,
        .no_collapse = true,
        .no_resize = true,
        .no_move = true,
        .no_bring_to_front_on_focus = true,
        .no_nav_focus = true,
    };

    // ChatGPT:
    // Important: note that we proceed even if Begin() returns false (aka window is collapsed).
    // This is because we want to keep our DockSpace() active. If a DockSpace() is inactive,
    // all active windows docked into it will lose their parent and become undocked.
    // We cannot preserve the docking relationship between an active window and an inactive docking, otherwise
    // any change of dockspace/settings would lead to windows being stuck in limbo and never being visible.
    cimgui.igPushStyleVar_Vec2(cimgui.ImGuiStyleVar_WindowPadding, cimgui.ImVec2{ .x = 0.0, .y = 0.0 });
    _ = cimgui.igBegin("Dock space", null, @bitCast(window_flags));
    cimgui.igPopStyleVar(1);

    const dockspace_id = cimgui.igGetID_Str("Dock space");
    _ = cimgui.igDockSpace(dockspace_id, cimgui.ImVec2{ .x = 0.0, .y = 0.0 }, cimgui.ImGuiDockNodeFlags_None, null);

    cimgui.igEnd();
}

const ImGuiSceneTextureData = struct {
    core: *Core,
    descriptor_set: vulkan.VkDescriptorSet,
};

fn imGuiSceneTextureCallback(size: Window.WindowSize, extra_data: ?*anyopaque) void {
    _ = size;
    var data: *ImGuiSceneTextureData = @ptrCast(@alignCast(extra_data));

    const sampler = data.core.renderer.system.resource_system.get_image_sampler("scene color") catch unreachable;
    const view = data.core.renderer.system.resource_system.get_image_view("scene color") catch unreachable;
    data.descriptor_set = @ptrCast(cimgui.ImGui_ImplVulkan_AddTexture(
        @ptrCast(sampler),
        @ptrCast(view),
        vulkan.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    ));
}
