// Demonstrates rendering the triangle to an offscreen attachment and then
// displaying it as an ImGui texture, like a viewport in an editor.

const std = @import("std");

const r4_core = @import("r4_core");
const vulkan = r4_core.vulkan;
const cimgui = r4_core.cimgui;
const l0vk = r4_core.l0vk;
const Core = r4_core.Core;
const Window = r4_core.Window;

const rendergraph = r4_core.rendergraph;
const Rendergraph = rendergraph.RenderGraph;
const ResourceDescription = r4_core.rendergraph.ResourceDescription;

pub const TrianglePass = struct {
    core: *Core,
    window: *Window,
    pipeline: l0vk.VkPipeline,
    pipeline_layout: l0vk.VkPipelineLayout,

    pub fn init(core: *Core, window: *Window) !TrianglePass {
        const pipeline_create_info = r4_core.pipeline.PipelineCreateInfo{
            .vertex_shader_filename = "shaders/compiled_output/triangle.vert.spv",
            .fragment_shader_filename = "shaders/compiled_output/triangle.frag.spv",
            .renderpass_name = "main",
        };
        const pipeline_and_layout = try core.renderer.system.pipeline_system.create(
            &core.renderer.system,
            "main pass pipeline",
            pipeline_create_info,
        );

        return TrianglePass{
            .core = core,
            .window = window,
            .pipeline = pipeline_and_layout.pipeline,
            .pipeline_layout = pipeline_and_layout.pipeline_layout,
        };
    }

    pub fn render(self_untyped: *anyopaque, command_buffer: l0vk.VkCommandBuffer) anyerror!void {
        const self: *TrianglePass = @ptrCast(@alignCast(self_untyped));

        vulkan.vkCmdBindPipeline(
            command_buffer,
            vulkan.VK_PIPELINE_BIND_POINT_GRAPHICS,
            self.pipeline,
        );

        const viewport = vulkan.VkViewport{
            .x = 0.0,
            .y = 0.0,
            .width = @floatFromInt(self.window.swapchain.swapchain.swapchain_extent.width),
            .height = @floatFromInt(self.window.swapchain.swapchain.swapchain_extent.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        vulkan.vkCmdSetViewport(command_buffer, 0, 1, &viewport);

        const scissor = vulkan.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.window.swapchain.swapchain.swapchain_extent,
        };
        vulkan.vkCmdSetScissor(command_buffer, 0, 1, &scissor);

        vulkan.vkCmdDraw(command_buffer, 3, 1, 0, 0);
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

        const viewport = vulkan.VkViewport{
            .x = 0.0,
            .y = 0.0,
            .width = @floatFromInt(self.window.swapchain.swapchain.swapchain_extent.width),
            .height = @floatFromInt(self.window.swapchain.swapchain.swapchain_extent.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        vulkan.vkCmdSetViewport(command_buffer, 0, 1, &viewport);

        const scissor = vulkan.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.window.swapchain.swapchain.swapchain_extent,
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

    var triangle_pass: TrianglePass = undefined;
    var main_pass: MainPass = undefined;

    // --- Build rendergraph.

    // ------ Triangle node

    const final_attachment = ResourceDescription{
        .name = "final",
        .kind = .attachment,
        .info = .{
            .attachment = .{
                .kind = .color_final,
                .format = window.swapchain.swapchain.swapchain_image_format,
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

    const triangle_attachment = ResourceDescription{
        .name = "triangle",
        .kind = .attachment,
        .info = .{
            .attachment = .{
                .kind = .color,
                .format = window.swapchain.swapchain.swapchain_image_format,
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

    var triangle_inputs = std.ArrayList(ResourceDescription).init(core.allocator);
    defer triangle_inputs.deinit();
    var triangle_outputs = std.ArrayList(ResourceDescription).init(core.allocator);
    defer triangle_outputs.deinit();
    try triangle_outputs.append(triangle_attachment);

    const triangle_node = rendergraph.Node{
        .name = "triangle",
        .inputs = triangle_inputs,
        .outputs = triangle_outputs,
        .render_fn = .{
            .function = &TrianglePass.render,
            .data = &triangle_pass,
        },
        .clear_color = .{ 0.5, 0.5, 0, 1 },
    };

    // ------ Final node

    var inputs = std.ArrayList(ResourceDescription).init(core.allocator);
    defer inputs.deinit();
    try inputs.append(triangle_attachment);
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

    var nodes = [_]rendergraph.Node{ triangle_node, node };
    var rg = Rendergraph.init_empty(core.allocator);
    defer rg.deinit();
    try rg.set_nodes_from_slice(&nodes);
    try rg.compile(&core.renderer.system, &core.renderer, &window);
    std.debug.print("{}\n", .{rg});

    triangle_pass = try TrianglePass.init(&core, &window);
    main_pass = try MainPass.init(&core, &window);

    const sampler = try core.renderer.system.resource_system.get_image_sampler("triangle");
    const view = try core.renderer.system.resource_system.get_image_view("triangle");
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

    while (!window.should_close()) {
        cimgui.ImGui_ImplVulkan_NewFrame();
        cimgui.ImGui_ImplGlfw_NewFrame();
        cimgui.igNewFrame();

        var open = true;
        var new_viewport_size_a: cimgui.ImVec2 = undefined;
        var new_viewport_size_b: cimgui.ImVec2 = undefined;
        var new_viewport_size: cimgui.ImVec2 = undefined;
        _ = cimgui.igBegin("Viewport", &open, 0);
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

        cimgui.igRender();

        // ---

        try rg.execute(&core.renderer, &window);
    }
}

const ImGuiSceneTextureData = struct {
    core: *Core,
    descriptor_set: vulkan.VkDescriptorSet,
};

fn imGuiSceneTextureCallback(size: Window.WindowSize, extra_data: ?*anyopaque) void {
    _ = size;
    var data: *ImGuiSceneTextureData = @ptrCast(@alignCast(extra_data));

    const sampler = data.core.renderer.system.resource_system.get_image_sampler("triangle") catch unreachable;
    const view = data.core.renderer.system.resource_system.get_image_view("triangle") catch unreachable;
    data.descriptor_set = @ptrCast(cimgui.ImGui_ImplVulkan_AddTexture(
        @ptrCast(sampler),
        @ptrCast(view),
        vulkan.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    ));
}
