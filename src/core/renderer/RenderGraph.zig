const std = @import("std");
const Renderer = @import("Renderer.zig");
const CommandBuffer = @import("CommandBuffer.zig");
const Resource = Renderer.Resource;
const VirtualRenderPass = @import("RenderPass.zig");
const VirtualRenderPassHandle = Renderer.RenderPassHandle;
const VulkanRenderPassHandle = Renderer.RenderPassHandle;

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
rp_handle_to_real_rp: std.AutoHashMap(usize, VulkanRenderPassHandle),

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

const ExecuteStep = struct {
    renderpass: VulkanRenderPassHandle,
    nodes: []usize,

    fn deinit(self: *ExecuteStep, allocator: std.mem.Allocator) void {
        allocator.free(self.nodes);
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
    while (i < command_buffer.commands.len) : (i += 1) {
        if (command_buffer.commands.items(.kind)[i] != .begin_render_pass) {
            continue;
        }

        const render_pass = command_buffer.commands.items(.data)[i];
        // Even though we haven't created the node yet, we know where it will be.
        const node_handle = nodes.items.len;

        // --- Find start and end commands.

        const command_start_idx = i + 1;
        var j = command_start_idx;
        while (true) {
            if (command_buffer.commands.items(.kind)[j] == .end_render_pass) {
                break;
            }

            if (j >= command_buffer.commands.len) {
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

        var productions = renderer.get_renderpass_from_handle(render_pass).produces;
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
        var node = &nodes.items[i];

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
        var node = &nodes.items[i];

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

    return .{
        .nodes = nodes,
        .root_node = root_node,
        .ui_node = ui_node,

        .execute_steps = std.ArrayList(ExecuteStep).init(renderer.allocator),
        .rp_handle_to_real_rp = std.AutoHashMap(usize, VulkanRenderPassHandle).init(renderer.allocator),

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
    var i = self.root_node;
    while (true) {
        const node = &self.nodes.items[i];

        // ---

        var vkrp_handle: VulkanRenderPassHandle = undefined;
        if (self.ui_node != null and self.ui_node.? == i) {
            vkrp_handle = renderer.ui.?.vulkan_renderpass_handle;
        } else {
            const rp = renderer.get_renderpass_from_handle(node.render_pass);
            const vkrp_init_info = .{
                .system = &renderer.system,
                .window = renderer.current_frame_context.?.window,

                .imgui_enabled = rp.enable_imgui,
                .tag = switch (rp.tag) {
                    .basic_primary => .basic_primary,
                },
                .render_area = .{
                    .width = rp.produces.items[0].width,
                    .height = rp.produces.items[0].height,
                },
            };
            vkrp_handle = try renderer.system.create_renderpass(&vkrp_init_info);
            try self.rp_handle_to_real_rp.put(node.render_pass, vkrp_handle);
        }

        // ---

        var nodes = try renderer.allocator.alloc(usize, 1);
        nodes[0] = i;

        // ---

        try self.execute_steps.append(.{
            .renderpass = vkrp_handle,
            .nodes = nodes,
        });

        // ---

        if (self.nodes.items[i].children.items.len == 0) {
            break;
        }

        i = self.nodes.items[i].children.items[0];
    }

    std.log.info("rendergraph: compiled {d} steps", .{self.execute_steps.items.len});
}

pub fn execute(self: *RenderGraph, renderer: *Renderer) !void {
    const swapchain = renderer.current_frame_context.?.window.swapchain;
    _ = swapchain;

    // ---

    var i: usize = 0;
    while (i < self.execute_steps.items.len) : (i += 1) {
        const step: *ExecuteStep = &self.execute_steps.items[i];

        // ---

        var command_buffer = renderer.current_frame_context.?.command_buffer_a;
        if (self.semaphore_to_use == .b) {
            command_buffer = renderer.current_frame_context.?.command_buffer_b;
        }

        try renderer.system.begin_command_buffer(command_buffer);

        // ---

        const vkrp = renderer.system.get_renderpass_from_handle(step.renderpass);
        var clear = false;
        if (i == 0) {
            clear = true;
        }
        vkrp.begin(command_buffer, renderer.current_frame_context.?.image_index, clear);

        var j: usize = 0;
        while (j < step.nodes.len) : (j += 1) {
            const node: *const Node = &self.nodes.items[step.nodes[j]];

            var k: usize = node.command_start_idx;
            while (k < node.command_end_idx) : (k += 1) {
                try renderer.command_buffer.execute_command(k, renderer, command_buffer);
            }
        }

        vkrp.end(command_buffer);

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

        if (i == 0) {
            wait_semaphore_handle = renderer.current_frame_context.?.image_available_semaphore;
        }

        if (i == self.execute_steps.items.len - 1) {
            signal_semaphore_handle = renderer.current_frame_context.?.render_finished_semaphore;
            fence = renderer.current_frame_context.?.fence;
        }

        // ---

        try renderer.system.end_command_buffer(command_buffer);
        try renderer.system.submit_command_buffer(
            &command_buffer,
            wait_semaphore_handle,
            signal_semaphore_handle,
            fence,
        );
    }
}
