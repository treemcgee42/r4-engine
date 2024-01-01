const std = @import("std");
const Renderer = @import("Renderer.zig");
const CommandBuffer = @import("CommandBuffer.zig");
const Resource = Renderer.Resource;
const VirtualRenderPass = @import("RenderPass.zig");
const VirtualRenderPassHandle = Renderer.RenderPassHandle;
const VulkanSystem = @import("vulkan/VulkanSystem.zig");
const VulkanImage = VulkanSystem.VulkanImage;
const vulkan = @import("vulkan");

const RenderGraph = @This();

nodes: std.ArrayList(Node),
root_node: usize,
ui_node: ?usize,

/// Populated during graph compilation.
execute_steps: std.ArrayList(ExecuteStep),
/// With respect to the vulkan renderpasses created in the graph, associate a (virtual)
/// renderpass handle to a vulkan renderpass. Useful during execution for binding pipelines,
/// since virtual pipelines are defined relative to a virtual renderpass.
///
/// Populated during grpah compilation.
rp_handle_to_real_rp: std.AutoHashMap(VirtualRenderPassHandle, VulkanSystem.RenderpassHandle),

semaphore_to_use: enum { a, b },

pub const RenderGraphError = error{
    dependency_never_produced,
};

pub const Node = struct {
    render_pass: Renderer.RenderPassHandle,
    /// Index (in `renderer.command_buffer.commands`) of the first command after
    /// the begin renderpass command.
    command_start_idx: usize,
    /// Index (in `renderer.command_buffer.commands`) of the end renderpass command,
    /// so that.
    command_end_idx: usize,
    /// Array of indices into `nodes`.
    parents: std.ArrayList(usize),
    /// Array of indices into `nodes`.
    children: std.ArrayList(usize),

    fn deinit(self: *Node) void {
        self.parents.deinit();
        self.children.deinit();
    }
};

const ImageTransition = struct {
    image: *VulkanImage,
    old_layout: vulkan.VkImageLayout,
    new_layout: vulkan.VkImageLayout,
};

const ExecuteStep = struct {
    renderpass: VulkanSystem.RenderpassHandle,
    nodes: []usize,
    pre_image_transitions: std.ArrayList(ImageTransition),
    image_transitions: std.ArrayList(ImageTransition),

    fn deinit(self: *ExecuteStep, allocator: std.mem.Allocator) void {
        allocator.free(self.nodes);
        self.image_transitions.deinit();
        self.pre_image_transitions.deinit();
    }
};

pub fn init(renderer: *Renderer, command_buffer: *const CommandBuffer) !RenderGraph {
    // First we need to go through the command buffer and do the following:
    // - Create a node for each renderpass. At this point we leave the `parents` undefined.
    // - Populate the resource producer map.
    //
    // Having done this, we can go back through the nodes (now nicely layed out in an array)
    // and populate the `parents` by looking at the resource producer map.

    var nodes = std.ArrayList(Node).init(renderer.allocator);

    // Associates to a resource the node that produces it.
    //
    // When constructing the graph, a renderpass can find it's *parents* by
    // going through its dependencies, looking each up in this map, and
    // adding that node as a parent.
    var resource_producer_map = std.AutoHashMap(Resource, usize).init(renderer.allocator);
    defer resource_producer_map.deinit();

    var i: usize = 0;
    while (i < command_buffer.commands.items.len) : (i += 1) {
        const command = command_buffer.commands.items[i];

        switch (command) {
            .begin_render_pass => {},
            else => {
                continue;
            },
        }

        const render_pass = command.begin_render_pass;
        // Even though we haven't created the node yet, we know where it will be.
        const node_handle = nodes.items.len;

        // --- Find start and end commands.

        const command_start_idx = i + 1;
        var j = command_start_idx;
        while (true) {
            switch (command_buffer.commands.items[j]) {
                .end_render_pass => {
                    break;
                },
                else => {},
            }

            if (j >= command_buffer.commands.items.len) {
                unreachable;
            }

            j += 1;
        }
        const command_end_idx = j;
        i = j;

        // --- Create node.

        try nodes.append(.{
            .render_pass = render_pass,
            .command_start_idx = command_start_idx,
            .command_end_idx = command_end_idx,

            .parents = std.ArrayList(usize).init(renderer.allocator),
            .children = std.ArrayList(usize).init(renderer.allocator),
        });

        // --- Handle productions.
        // Associate to each resource a the nodes which produces it.

        const productions = renderer.get_renderpass_from_handle(render_pass).produces;
        for (productions.items) |resource| {
            try resource_producer_map.put(resource, node_handle);
        }
    }

    // ---
    // Now, for each node, fill in its parents by seeing which resources it depends on
    // and adding the producers of those resources as the parents.

    i = 0;
    while (i < nodes.items.len) : (i += 1) {
        var node = &nodes.items[i];

        const dependencies = renderer.get_renderpass_from_handle(node.render_pass).depends_on;
        for (dependencies.items) |dependency_handle| {
            const producer_node_handle = resource_producer_map.get(dependency_handle);
            if (producer_node_handle == null) {
                return RenderGraphError.dependency_never_produced;
            }

            try node.parents.append(producer_node_handle.?);
        }
    }

    // ---
    // Now go through each node, look at its parents, and add it as a child of the parent.

    i = 0;
    while (i < nodes.items.len) : (i += 1) {
        const node = &nodes.items[i];

        var j: usize = 0;
        while (j < node.parents.items.len) : (j += 1) {
            var parent = &nodes.items[node.parents.items[j]];
            try parent.children.append(i);
        }
    }

    // ---
    // The root node can be determined at this point.

    var root_node: usize = 0;
    i = 0;
    while (i < nodes.items.len) : (i += 1) {
        const node = &nodes.items[i];

        var j: usize = 0;
        while (j < node.children.items.len) : (j += 1) {
            if (node.children.items[j] == root_node) {
                root_node = j;
                break;
            }
        }
    }

    // ---
    // If Ui is enabled, that node depends on all other nodes.

    var ui_node: ?usize = null;
    if (renderer.ui != null) {
        var leaves = std.ArrayList(usize).init(renderer.allocator);
        i = 0;
        while (i < nodes.items.len) : (i += 1) {
            if (nodes.items[i].children.items.len == 0) {
                try leaves.append(i);
            }
        }

        var parents = std.ArrayList(usize).init(renderer.allocator);
        try parents.appendSlice(leaves.items);
        try nodes.append(.{
            .render_pass = undefined,
            .command_start_idx = 0,
            .command_end_idx = 0,

            .parents = parents,
            .children = std.ArrayList(usize).init(renderer.allocator),
        });
        ui_node = nodes.items.len - 1;

        i = 0;
        while (i < leaves.items.len) : (i += 1) {
            var node = &nodes.items[leaves.items[i]];
            try node.children.append(ui_node.?);
        }
        leaves.deinit();
    }

    // ---

    std.log.info("rendergraph: created {d} nodes (root {d})", .{ nodes.items.len, root_node });
    i = 0;
    while (i < nodes.items.len) : (i += 1) {
        const name = if (ui_node != null and i == ui_node.?) "ui" else renderer.get_renderpass_from_handle(nodes.items[i].render_pass).name;
        std.log.info("\t{d}: rp {s}, {d} parents, {d} children", .{
            i,
            name,
            nodes.items[i].parents.items.len,
            nodes.items[i].children.items.len,
        });
    }

    return .{
        .nodes = nodes,
        .root_node = root_node,
        .ui_node = ui_node,

        .execute_steps = std.ArrayList(ExecuteStep).init(renderer.allocator),
        .rp_handle_to_real_rp = std.AutoHashMap(
            VirtualRenderPassHandle,
            VulkanSystem.RenderpassHandle,
        ).init(renderer.allocator),

        .semaphore_to_use = .a,
    };
}

pub fn deinit(self: *RenderGraph, renderer: *Renderer) void {
    _ = renderer;

    var i: usize = 0;
    while (i < self.nodes.items.len) : (i += 1) {
        self.nodes.items[i].deinit();
    }
    self.nodes.deinit();

    i = 0;
    while (i < self.execute_steps.items.len) : (i += 1) {
        self.execute_steps.items[i].deinit(self.rp_handle_to_real_rp.allocator);
    }
    self.execute_steps.deinit();

    self.rp_handle_to_real_rp.deinit();
}

/// This is where we actually construct the API renderpasses and synchronization
/// mechanisms.
pub fn compile(self: *RenderGraph, renderer: *Renderer) !void {
    const InitialFinalLayouts = struct {
        initial: vulkan.VkImageLayout,
        final: vulkan.VkImageLayout,
    };
    var initial_final_layouts = std.AutoHashMap(*VulkanSystem.VulkanImage, InitialFinalLayouts).init(
        renderer.allocator,
    );
    defer initial_final_layouts.deinit();

    var i = self.root_node;
    while (true) {
        const node = &self.nodes.items[i];

        // --- Create renderpasses.

        var vkrp_handle: VulkanSystem.RenderpassHandle = undefined;
        if (self.ui_node != null and self.ui_node.? == i) {
            vkrp_handle = renderer.ui.?.vulkan_renderpass_handle;
        } else {
            const rp = renderer.get_renderpass_from_handle(node.render_pass);
            const production = renderer.resource_system.get_resource_from_handle(rp.produces.items[0]);

            // This is a good place to make a determination on whether the renderpass should be
            // static or dynamic.

            const dynamic = if (rp.tag == .render_to_image) true else false;
            if (dynamic) {
                const create_info = VulkanSystem.DynamicRenderpassCreateInfo{
                    .system = &renderer.system,
                    .window = renderer.current_frame_context.?.window,

                    .imgui_enabled = rp.enable_imgui,
                    .tag = rp.tag,
                    .render_area = .{
                        .width = production.width,
                        .height = production.height,
                    },
                    .depth_buffered = rp.depth_test,
                    .name = rp.name,
                };
                vkrp_handle = try renderer.system.create_dynamic_renderpass(&create_info);
                try self.rp_handle_to_real_rp.put(node.render_pass, vkrp_handle);
            } else {
                const create_info = VulkanSystem.StaticRenderpassCreateInfo{
                    .system = &renderer.system,
                    .window = renderer.current_frame_context.?.window,

                    .imgui_enabled = rp.enable_imgui,
                    .tag = rp.tag,
                    .render_area = .{
                        .width = production.width,
                        .height = production.height,
                    },
                    .depth_buffered = rp.depth_test,
                    .name = rp.name,
                };
                vkrp_handle = try renderer.system.create_static_renderpass(&create_info);
                try self.rp_handle_to_real_rp.put(node.render_pass, vkrp_handle);
            }
        }

        // --- Specify image layout transitions.

        var image_transitions = std.ArrayList(ImageTransition).init(renderer.allocator);

        const node_productions = renderer.get_renderpass_from_handle(node.render_pass).produces;
        var j: usize = 0;
        while (j < node_productions.items.len) : (j += 1) {
            const production = renderer.resource_system.get_resource_from_handle(node_productions.items[j]);
            if (production.kind == .color_texture) {
                // For each child that depends on it...
                for (node.children.items) |child| {
                    const child_node_ptr = &self.nodes.items[child];
                    const child_dependencies = renderer.get_renderpass_from_handle(
                        child_node_ptr.render_pass,
                    ).depends_on;
                    for (child_dependencies.items) |dep| {
                        if (renderer.resource_system.get_resource_from_handle(dep).kind == .color_texture) {
                            // Transition color_attachment_optimal to shader_read_only_optimal.
                            const vkrp_ptr = renderer.system.get_renderpass_from_handle(vkrp_handle);
                            const image_ptr = &vkrp_ptr.dynamic.images.map.getPtr("color").?.color.image;

                            const old_layout = vulkan.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
                            const new_layout = vulkan.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
                            try initial_final_layouts.put(
                                image_ptr,
                                .{
                                    .initial = old_layout,
                                    .final = new_layout,
                                },
                            );
                            try image_transitions.append(.{
                                .image = image_ptr,
                                .old_layout = old_layout,
                                .new_layout = new_layout,
                            });
                        }
                    }
                }
            }
        }

        // ---

        var nodes = try renderer.allocator.alloc(usize, 1);
        nodes[0] = i;

        // ---

        try self.execute_steps.append(.{
            .renderpass = vkrp_handle,
            .nodes = nodes,
            .pre_image_transitions = std.ArrayList(ImageTransition).init(renderer.allocator),
            .image_transitions = image_transitions,
        });

        // ---

        if (self.nodes.items[i].children.items.len == 0) {
            break;
        }

        i = self.nodes.items[i].children.items[0];
    }

    // --- Transition images back to their initial layout.

    var keys_iter = initial_final_layouts.keyIterator();
    while (keys_iter.next()) |image_ptr| {
        const initial_final = initial_final_layouts.get(image_ptr.*).?;
        try self.execute_steps.items[self.root_node].pre_image_transitions.append(.{
            .image = image_ptr.*,
            .old_layout = initial_final.final,
            .new_layout = initial_final.initial,
        });
    }

    // ---

    std.log.info("rendergraph: compiled {d} steps", .{self.execute_steps.items.len});
    i = 0;
    while (i < self.execute_steps.items.len) : (i += 1) {
        const step = &self.execute_steps.items[i];
        const name = switch (renderer.system.get_renderpass_from_handle(step.renderpass).*) {
            .static => |*rp| rp.name,
            .dynamic => |*rp| rp.name,
        };
        std.log.info("\t{s}: {d} nodes", .{ name, step.nodes.len });
    }
}

pub fn execute(self: *RenderGraph, renderer: *Renderer) !void {
    const swapchain = renderer.current_frame_context.?.window.swapchain;
    _ = swapchain;

    // ---

    var command_buffer = renderer.current_frame_context.?.command_buffer_a;
    if (self.semaphore_to_use == .b) {
        command_buffer = renderer.current_frame_context.?.command_buffer_b;
    }

    try renderer.system.begin_command_buffer(command_buffer);

    // ---

    for (self.execute_steps.items[0].pre_image_transitions.items) |transition| {
        try transition.image.transition_image_layout(
            command_buffer,
            transition.old_layout,
            transition.new_layout,
        );
    }

    // ---

    var i: usize = 0;
    while (i < self.execute_steps.items.len) : (i += 1) {
        const step: *ExecuteStep = &self.execute_steps.items[i];

        // ---

        const vkrp_ptr = renderer.system.get_renderpass_from_handle(step.renderpass);
        switch (vkrp_ptr.*) {
            .static => {
                // TODO: we shouldn't be setting this here.
                var clear = false;
                if (i == 0 or vkrp_ptr.static.load_op_clear) {
                    clear = true;
                }
                vkrp_ptr.static.begin(
                    command_buffer,
                    renderer.current_frame_context.?.image_index,
                    clear,
                );
            },
            .dynamic => {
                try vkrp_ptr.dynamic.begin(command_buffer);
            },
        }

        var j: usize = 0;
        while (j < step.nodes.len) : (j += 1) {
            const node: *const Node = &self.nodes.items[step.nodes[j]];

            var k: usize = node.command_start_idx;
            while (k < node.command_end_idx) : (k += 1) {
                try renderer.command_buffer.execute_command(k, renderer, command_buffer);
            }
        }

        switch (vkrp_ptr.*) {
            .static => {
                vkrp_ptr.static.end(command_buffer);
            },
            .dynamic => {
                vkrp_ptr.dynamic.end(command_buffer);
            },
        }

        for (step.image_transitions.items) |transition| {
            try transition.image.transition_image_layout(
                command_buffer,
                transition.old_layout,
                transition.new_layout,
            );
        }
    }

    // ---

    var wait_semaphore_handle = renderer.current_frame_context.?.a_semaphore;
    var signal_semaphore_handle = renderer.current_frame_context.?.b_semaphore;
    var fence: ?usize = null;
    if (self.semaphore_to_use == .b) {
        wait_semaphore_handle = renderer.current_frame_context.?.b_semaphore;
        signal_semaphore_handle = renderer.current_frame_context.?.a_semaphore;
        self.semaphore_to_use = .a;
    } else {
        self.semaphore_to_use = .b;
    }

    // if (i == 0) {
    wait_semaphore_handle = renderer.current_frame_context.?.image_available_semaphore;
    // }

    // if (i == self.execute_steps.items.len - 1) {
    signal_semaphore_handle = renderer.current_frame_context.?.render_finished_semaphore;
    fence = renderer.current_frame_context.?.fence;
    // }

    // ---

    try renderer.system.end_command_buffer(command_buffer);
    try renderer.system.submit_command_buffer(
        &command_buffer,
        wait_semaphore_handle,
        signal_semaphore_handle,
        fence,
    );
}
