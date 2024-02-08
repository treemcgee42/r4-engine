const l0vk = @import("../layer0/vulkan/vulkan.zig");
const vulkan = @import("vulkan");
const Window = @import("../../Window.zig");
const VulkanSystem = @import("./VulkanSystem.zig");
const std = @import("std");
pub const ResourceDescription = @import("./resource.zig").ResourceDescription;
const dutil = @import("debug_utils");
const Renderer = @import("../Renderer.zig");

const resource = @import("./resource.zig");

// ---

pub const RenderFn = struct {
    function: *const fn (*anyopaque, l0vk.VkCommandBuffer) anyerror!void,
    data: *anyopaque,
};

pub const Node = struct {
    name: []const u8,

    inputs: std.ArrayList(ResourceDescription),
    outputs: std.ArrayList(ResourceDescription),

    render_fn: RenderFn,
};

/// Associated to a node during graph construction/compilation.
pub const NodeGraphData = struct {
    /// An edge is a relationship "this_node --> other_node".
    /// The `usize` represents the index of the other node in the graph.
    edges: std.ArrayList(usize),
    renderpass: VulkanSystem.RenderpassHandle,
};

// ---

pub const RenderGraph = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(Node),
    node_data: std.ArrayList(NodeGraphData),
    /// Elements are indices into the `nodes` (and `node_data`) array.
    sorted_nodes: std.ArrayList(usize),

    pub fn init_empty(allocator: std.mem.Allocator) RenderGraph {
        const nodes = std.ArrayList(Node).init(allocator);
        const node_data = std.ArrayList(NodeGraphData).init(allocator);
        const sorted_nodes = std.ArrayList(usize).init(allocator);

        return .{
            .allocator = allocator,
            .nodes = nodes,
            .node_data = node_data,
            .sorted_nodes = sorted_nodes,
        };
    }

    /// Also deinitializes the `nodes` and `node_data` items.
    pub fn deinit(self: *RenderGraph) void {
        self.sorted_nodes.deinit();

        var i: usize = 0;
        while (i < self.nodes.items.len) : (i += 1) {
            self.nodes.items[i].inputs.deinit();
            self.nodes.items[i].outputs.deinit();
        }

        self.nodes.deinit();

        i = 0;
        while (i < self.node_data.items.len) : (i += 1) {
            self.node_data.items[i].edges.deinit();
        }

        self.node_data.deinit();
    }

    /// Caller should probably recompile the graph after calling this function.
    pub fn set_nodes_from_slice(self: *RenderGraph, nodes: []Node) !void {
        self.deinit();
        self.nodes = std.ArrayList(Node).init(self.allocator);
        self.node_data = std.ArrayList(NodeGraphData).init(self.allocator);

        var i: usize = 0;
        while (i < nodes.len) : (i += 1) {
            var node = Node{
                .name = nodes[i].name,
                .inputs = std.ArrayList(ResourceDescription).init(self.allocator),
                .outputs = std.ArrayList(ResourceDescription).init(self.allocator),
                .render_fn = nodes[i].render_fn,
            };

            try node.inputs.appendSlice(nodes[i].inputs.items);
            try node.outputs.appendSlice(nodes[i].outputs.items);

            try self.nodes.append(node);

            try self.node_data.append(.{
                .edges = std.ArrayList(usize).init(self.allocator),
                .renderpass = 0,
            });
        }
    }

    /// Completes the stage within the `compile()` function which determines the edges of the graph.
    /// Separating this out makes it easier to test.
    pub fn compile_topology(self: *RenderGraph) !void {
        // --- Populate input_resource_to_node_map.
        // Key: resource (name), value: list of nodes (indices) with that resource as input

        var input_resource_to_node_map = std.StringHashMap(std.ArrayList(usize)).init(self.allocator);

        var i: usize = 0;
        while (i < self.nodes.items.len) : (i += 1) {
            const node_ptr = &self.nodes.items[i];

            var j: usize = 0;
            while (j < node_ptr.inputs.items.len) : (j += 1) {
                const input = node_ptr.inputs.items[j];

                if (!input_resource_to_node_map.contains(input.name)) {
                    try input_resource_to_node_map.put(input.name, std.ArrayList(usize).init(self.allocator));
                }

                try input_resource_to_node_map.getPtr(input.name).?.append(i);
            }
        }

        // --- Determine edges.
        // For each node, look at its outputs. Using the map above, determine which nodes take
        // these outputs as inputs. These are the edges.

        i = 0;
        while (i < self.nodes.items.len) : (i += 1) {
            const node_ptr = &self.nodes.items[i];

            var j: usize = 0;
            while (j < node_ptr.outputs.items.len) : (j += 1) {
                const output = node_ptr.outputs.items[j];

                const output_consumers = input_resource_to_node_map.get(output.name);
                if (output_consumers == null) {
                    dutil.log("rendergraph", .err, "output {s} has no consumers", .{output.name});
                    continue;
                }

                try self.node_data.items[i].edges.appendSlice(output_consumers.?.items);

                // Remove edges from the node to itself.
                var k: usize = 0;
                while (k < self.node_data.items[i].edges.items.len) : (k += 1) {
                    if (self.node_data.items[i].edges.items[k] == i) {
                        _ = self.node_data.items[i].edges.swapRemove(k);
                    }
                }
            }
        }

        // --- Cleanup

        var value_iter = input_resource_to_node_map.valueIterator();
        while (value_iter.next()) |value| {
            value.deinit();
        }
        input_resource_to_node_map.deinit();
    }

    /// Completes the stage within the `compile()` function which sorts the nodes topologically.
    /// Assumes edges have already been determined.
    pub fn compile_sort(self: *RenderGraph) !void {
        // For each edge A --> B, it must be that A runs before B, i.e. A is sorted to be before B.

        var i: usize = 0;
        while (i < self.nodes.items.len) : (i += 1) {
            try compile_sort_recursor(self, i);
        }

        // Reverse the list.
        const len = self.sorted_nodes.items.len;
        i = 0;
        while (i < len / 2) : (i += 1) {
            const tmp = self.sorted_nodes.items[i];
            self.sorted_nodes.items[i] = self.sorted_nodes.items[len - i - 1];
            self.sorted_nodes.items[len - i - 1] = tmp;
        }
    }

    fn compile_sort_recursor(self: *RenderGraph, node_index: usize) !void {
        var i: usize = 0;
        while (i < self.sorted_nodes.items.len) : (i += 1) {
            if (self.sorted_nodes.items[i] == node_index) {
                return;
            }
        }

        const node_data = &self.node_data.items[node_index];

        var j: usize = 0;
        while (j < node_data.edges.items.len) : (j += 1) {
            const child_index = node_data.edges.items[j];
            try compile_sort_recursor(self, child_index);
        }

        try self.sorted_nodes.append(node_index);
    }

    fn compile_create_resources(self: *RenderGraph, system: *VulkanSystem, renderer: *Renderer, window: *Window) !void {
        var constructed_resources = std.StringHashMap(bool).init(self.allocator);
        defer constructed_resources.deinit();

        var i: usize = 0;
        while (i < self.nodes.items.len) : (i += 1) {
            const node_ptr = &self.nodes.items[i];
            const outputs = node_ptr.outputs.items;

            var j: usize = 0;
            while (j < outputs.len) : (j += 1) {
                const output_desc = outputs[j];
                const output_name = outputs[j].name;

                if (constructed_resources.contains(output_name)) {
                    continue;
                }
                try system.resource_system.create_resource(output_desc);
                try system.resource_system.create_vulkan_resources(renderer, window, output_name);
                try constructed_resources.put(output_name, true);
            }
        }
    }

    fn compile_create_renderpasses(self: *RenderGraph, system: *VulkanSystem, renderer: *Renderer, window: *Window) !void {
        var i: usize = 0;
        while (i < self.nodes.items.len) : (i += 1) {
            const node_ptr = &self.nodes.items[i];

            var attachments = std.ArrayList(VulkanSystem.DynamicRenderpass2Attachment).init(self.allocator);
            defer attachments.deinit();

            var render_area_width: u32 = undefined;
            var render_area_height: u32 = undefined;

            var j: usize = 0;
            while (j < node_ptr.outputs.items.len) : (j += 1) {
                const output_name = node_ptr.outputs.items[j].name;

                const is_attachment = system.resource_system.is_attachment(output_name);
                if (!is_attachment) {
                    continue;
                }

                const attachment_kind = system.resource_system.get_attachment_kind(output_name) catch unreachable;
                const attachment_format = system.resource_system.get_attachment_format(output_name) catch unreachable;

                if (attachment_kind == .color or attachment_kind == .color_final) {
                    const dims = try system.resource_system.get_width_and_height(output_name, renderer, window);
                    render_area_width = dims.width;
                    render_area_height = dims.height;
                }

                var image_view: l0vk.VkImageView = undefined;
                if (attachment_kind != .color_final) {
                    image_view = try system.resource_system.get_image_view(output_name);
                }

                try attachments.append(VulkanSystem.DynamicRenderpass2Attachment{
                    .image_view = image_view,
                    .kind = attachment_kind,
                    .format = attachment_format,
                });
            }

            const create_info = VulkanSystem.DynamicRenderpass2CreateInfo{
                .name = node_ptr.name,
                .system = system,
                .attachments = attachments.items,
                .render_area = .{ .width = render_area_width, .height = render_area_height },
            };
            const renderpass = try system.renderpass_system.create_new_renderpass(&create_info);
            self.node_data.items[i].renderpass = renderpass;
        }
    }

    pub fn compile(self: *RenderGraph, system: *VulkanSystem, renderer: *Renderer, window: *Window) !void {
        dutil.log(
            "render graph",
            .info,
            "{s}: starting",
            .{@src().fn_name},
        );

        try self.compile_topology();
        try self.compile_sort();
        try self.compile_create_resources(system, renderer, window);
        try self.compile_create_renderpasses(system, renderer, window);

        dutil.log(
            "render graph",
            .info,
            "{s}: finished ({d} nodes)",
            .{ @src().fn_name, self.sorted_nodes.items.len },
        );
    }

    pub fn execute(
        self: *RenderGraph,
        renderer: *Renderer,
        window: *Window,
    ) !void {
        try renderer.begin_frame_new(window);

        var command_buffer = renderer.current_frame_context.?.command_buffer_a;
        try renderer.system.begin_command_buffer(command_buffer);

        var i: usize = 0;
        while (i < self.sorted_nodes.items.len) : (i += 1) {
            const node_idx = self.sorted_nodes.items[i];
            const node_ptr = &self.nodes.items[node_idx];
            const node_data_ptr = &self.node_data.items[node_idx];

            renderer.system.renderpass_system.pre_begin(
                window,
                renderer.current_frame_context.?.image_index,
                node_data_ptr.renderpass,
            );

            // --- Transition inputs.

            var j: usize = 0;
            while (j < node_ptr.inputs.items.len) : (j += 1) {
                const input = node_ptr.inputs.items[j];

                if (!renderer.system.resource_system.is_attachment(input.name)) {
                    continue;
                }

                const attachment_kind = renderer.system.resource_system.get_attachment_kind(input.name) catch unreachable;

                if (attachment_kind == .color_final) {
                    try renderer.system.resource_system.transition_image_layout(
                        renderer,
                        window,
                        command_buffer,
                        input.name,
                        vulkan.VK_IMAGE_LAYOUT_UNDEFINED,
                        vulkan.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                    );
                }
            }

            // ---

            renderer.system.renderpass_system.begin(
                &renderer.system,
                node_data_ptr.renderpass,
                command_buffer,
            );

            try node_ptr.render_fn.function(node_ptr.render_fn.data, command_buffer);

            renderer.system.renderpass_system.end(
                &renderer.system,
                node_data_ptr.renderpass,
                command_buffer,
            );

            // --- Transition outputs.

            j = 0;
            while (j < node_ptr.outputs.items.len) : (j += 1) {
                const output = node_ptr.outputs.items[j];

                if (!renderer.system.resource_system.is_attachment(output.name)) {
                    continue;
                }

                const attachment_kind = renderer.system.resource_system.get_attachment_kind(output.name) catch unreachable;

                if (attachment_kind == .color_final) {
                    try renderer.system.resource_system.transition_image_layout(
                        renderer,
                        window,
                        command_buffer,
                        output.name,
                        vulkan.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                        vulkan.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                    );
                }
            }
        }

        try renderer.system.end_command_buffer(command_buffer);
        try renderer.system.submit_command_buffer(
            &command_buffer,
            renderer.current_frame_context.?.image_available_semaphore,
            renderer.current_frame_context.?.render_finished_semaphore,
            renderer.current_frame_context.?.fence,
        );

        try renderer.end_frame_new(window);
    }

    pub fn format(
        value: RenderGraph,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;

        try writer.writeAll("RenderGraph {{\n");

        try writer.writeAll("\tsorted_nodes: ");
        try writer.writeAll("[ ");
        var i: usize = 0;
        while (i < value.sorted_nodes.items.len) : (i += 1) {
            const node_idx = value.sorted_nodes.items[i];
            try writer.print("{s}, ", .{value.nodes.items[node_idx].name});
        }
        try writer.writeAll("],\n");

        try writer.writeAll("}}");
    }
};
