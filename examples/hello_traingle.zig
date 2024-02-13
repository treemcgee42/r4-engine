const std = @import("std");

const r4_core = @import("r4_core");
const vulkan = r4_core.vulkan;
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
        const pipeline_and_layout = try r4_core.pipeline.build_pipeline_base(
            &core.renderer,
            "shaders/compiled_output/triangle.vert.spv",
            "shaders/compiled_output/triangle.frag.spv",
            "main",
            true,
        );

        return MainPass{
            .core = core,
            .window = window,
            .pipeline = pipeline_and_layout.pipeline,
            .pipeline_layout = pipeline_and_layout.pipeline_layout,
        };
    }

    pub fn deinit(self: *MainPass, core: *Core) void {
        const ctx = self.core.allocator.create(DeinitVulkanCtx) catch unreachable;
        ctx.* = .{
            .pipeline = self.pipeline,
            .pipeline_layout = self.pipeline_layout,
            .core = core,
        };

        core.renderer.system.deinit_queue.insert(
            @ptrCast(ctx),
            &deinit_vulkan_callback,
        ) catch unreachable;
    }

    pub const DeinitVulkanCtx = struct {
        pipeline: l0vk.VkPipeline,
        pipeline_layout: l0vk.VkPipelineLayout,
        core: *Core,
    };

    pub fn deinit_vulkan_callback(ctx_untyped: *anyopaque) void {
        const ctx: *DeinitVulkanCtx = @ptrCast(@alignCast(ctx_untyped));
        l0vk.vkDestroyPipeline(ctx.core.renderer.system.logical_device, ctx.pipeline, null);
        l0vk.vkDestroyPipelineLayout(ctx.core.renderer.system.logical_device, ctx.pipeline_layout, null);
        ctx.core.renderer.system.allocator.destroy(ctx);
    }

    pub fn render(self_untyped: *anyopaque, command_buffer: l0vk.VkCommandBuffer) anyerror!void {
        const self: *MainPass = @ptrCast(@alignCast(self_untyped));

        vulkan.vkCmdBindPipeline(
            command_buffer,
            vulkan.VK_PIPELINE_BIND_POINT_GRAPHICS,
            self.pipeline,
        );

        const size = self.window.size();
        _ = size;

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

    const window_init_info = Window.WindowInitInfo{};
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
    try inputs.append(final_attachment);
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
        .clear_color = .{ 0.3, 0.1, 0.2, 1.0 },
    };

    var nodes = [_]rendergraph.Node{node};
    try rg.set_nodes_from_slice(&nodes);
    try rg.compile(&core.renderer.system, &core.renderer, &window);

    main_pass = try MainPass.init(&core, &window);
    defer main_pass.deinit(&core);

    while (!window.should_close()) {
        try rg.execute(&core.renderer, &window);
    }
}
