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

pub const MainPass = struct {
    core: *Core,
    window: *Window,
    pipeline: l0vk.VkPipeline,
    pipeline_layout: l0vk.VkPipelineLayout,

    pub fn init(core: *Core, window: *Window) !MainPass {
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

        return MainPass{
            .core = core,
            .window = window,
            .pipeline = pipeline_and_layout.pipeline,
            .pipeline_layout = pipeline_and_layout.pipeline_layout,
        };
    }

    pub fn render(self_untyped: *anyopaque, command_buffer: l0vk.VkCommandBuffer) anyerror!void {
        const self: *MainPass = @ptrCast(@alignCast(self_untyped));

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

    var main_pass: MainPass = undefined;

    // --- Build rendergraph.

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

    var inputs = std.ArrayList(ResourceDescription).init(core.allocator);
    defer inputs.deinit();
    var outputs = std.ArrayList(ResourceDescription).init(core.allocator);
    defer outputs.deinit();
    try outputs.append(final_attachment);

    var rg = Rendergraph.init_empty(core.allocator);
    defer rg.deinit();
    const node = rendergraph.Node{
        .name = "main",
        .inputs = inputs,
        .outputs = outputs,
        .render_fn = .{
            .function = &MainPass.render,
            .data = &main_pass,
        },
        .clear_color = .{ 0.0, 0.5, 0.5, 1.0 },
    };

    var nodes = [_]rendergraph.Node{node};
    try rg.set_nodes_from_slice(&nodes);
    try rg.compile(&core.renderer.system, &core.renderer, &window);

    main_pass = try MainPass.init(&core, &window);

    while (!window.should_close()) {
        try rg.execute(&core.renderer, &window);
    }
}
