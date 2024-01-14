const l0vk = @import("../layer0/vulkan/vulkan.zig");
const VulkanSystem = @import("./VulkanSystem.zig");
const std = @import("std");
pub const ResourceDescription = @import("./resource.zig").ResourceDescription;
const dutil = @import("debug_utils");

// ---

pub const Node = struct {
    name: []const u8,

    inputs: std.ArrayList(ResourceDescription),
    outputs: std.ArrayList(ResourceDescription),
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
