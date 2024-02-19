const std = @import("std");
const r4_core = @import("r4_core");

const rendergraph = r4_core.rendergraph;
const RenderGraph = r4_core.rendergraph.RenderGraph;
const Node = rendergraph.Node;
const ResourceDescription = rendergraph.ResourceDescription;

const TestNode = struct {
    name: []const u8,
    inputs: [][]const u8,
    outputs: [][]const u8,
};

fn topology_test_helper(topology_json: []const u8) !void {
    const allocator = std.testing.allocator;

    const test_nodes = try std.json.parseFromSlice(
        []TestNode,
        allocator,
        topology_json,
        .{},
    );
    defer test_nodes.deinit();

    var nodes = try allocator.alloc(Node, test_nodes.value.len);
    defer {
        var i: usize = 0;
        while (i < nodes.len) : (i += 1) {
            nodes[i].inputs.deinit();
            nodes[i].outputs.deinit();
        }
        allocator.free(nodes);
    }

    var i: usize = 0;
    while (i < nodes.len) : (i += 1) {
        var node = Node{
            .name = test_nodes.value[i].name,
            .inputs = std.ArrayList(ResourceDescription).init(allocator),
            .outputs = std.ArrayList(ResourceDescription).init(allocator),
            .render_fn = undefined,
        };

        var j: usize = 0;
        while (j < test_nodes.value[i].inputs.len) : (j += 1) {
            const resource_description = ResourceDescription{
                .name = test_nodes.value[i].inputs[j],
                .kind = .name_only,
                .info = .{ .name_only = {} },
            };

            try node.inputs.append(resource_description);
        }

        j = 0;
        while (j < test_nodes.value[i].outputs.len) : (j += 1) {
            const resource_description = ResourceDescription{
                .name = test_nodes.value[i].outputs[j],
                .kind = .name_only,
                .info = .{ .name_only = {} },
            };

            try node.outputs.append(resource_description);
        }

        nodes[i] = node;
    }

    var graph = RenderGraph.init_empty(allocator);
    defer graph.deinit();
    try graph.set_nodes_from_slice(nodes);

    try graph.compile_topology();

    // --- Verify edges.

    // Key: resource (name), value: list of nodes (names) with that resource as input
    var resource_to_consumers_map = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);
    defer {
        var value_iter = resource_to_consumers_map.valueIterator();
        while (value_iter.next()) |value| {
            value.deinit();
        }
        resource_to_consumers_map.deinit();
    }

    i = 0;
    while (i < test_nodes.value.len) : (i += 1) {
        var j: usize = 0;
        while (j < test_nodes.value[i].inputs.len) : (j += 1) {
            const input_name = test_nodes.value[i].inputs[j];
            if (!resource_to_consumers_map.contains(input_name)) {
                try resource_to_consumers_map.put(input_name, std.ArrayList([]const u8).init(allocator));
            }

            try resource_to_consumers_map.getPtr(input_name).?.append(test_nodes.value[i].name);
        }
    }

    // Key: node (name), value: list of nodes (names) which are the endpoint of an edge from the
    // node.
    var edges = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);
    defer {
        var value_iter = edges.valueIterator();
        while (value_iter.next()) |value| {
            value.deinit();
        }
        edges.deinit();
    }

    i = 0;
    while (i < test_nodes.value.len) : (i += 1) {
        var endpoints = std.ArrayList([]const u8).init(allocator);

        var j: usize = 0;
        while (j < test_nodes.value[i].outputs.len) : (j += 1) {
            const output_name = test_nodes.value[i].outputs[j];

            const output_consumers = resource_to_consumers_map.get(output_name) orelse continue;
            var k: usize = 0;
            while (k < output_consumers.items.len) : (k += 1) {
                try endpoints.append(output_consumers.items[k]);
            }
        }

        try edges.put(test_nodes.value[i].name, endpoints);
    }

    i = 0;
    while (i < graph.nodes.items.len) : (i += 1) {
        const node_name = graph.nodes.items[i].name;
        const node_edges = graph.node_data.items[i].edges;

        // Assert each node has the same number of edge endpoints.

        const test_edges = edges.get(node_name) orelse {
            try std.testing.expect(node_edges.items.len == 0);
            continue;
        };

        try std.testing.expect(node_edges.items.len == test_edges.items.len);

        // Assert each edge endpoint in the graph is an edge endpoint in the
        // test description.

        var j: usize = 0;
        while (j < node_edges.items.len) : (j += 1) {
            const endpoint_name = graph.nodes.items[node_edges.items[j]].name;

            var k: usize = 0;
            var contains = false;
            while (k < test_edges.items.len) : (k += 1) {
                if (std.mem.eql(u8, endpoint_name, test_edges.items[k])) {
                    contains = true;
                }
            }

            try std.testing.expect(contains);
        }
    }

    // --- Verify sorting.
    // For each edge, ensure that the index of the source is before the index of the endpoint.

    try graph.compile_sort();
    std.debug.print("RG: {}\n", .{graph});

    var edge_iter = edges.keyIterator();
    while (edge_iter.next()) |key| {
        var source_idx: usize = undefined;
        var found_source = false;

        var j: usize = 0;
        while (j < graph.sorted_nodes.items.len) : (j += 1) {
            const node_idx = graph.sorted_nodes.items[j];
            if (std.mem.eql(u8, key.*, graph.nodes.items[node_idx].name)) {
                source_idx = j;
                found_source = true;
                break;
            }
        }
        try std.testing.expect(found_source);

        j = 0;
        const endpoints = edges.get(key.*) orelse unreachable;
        while (j < endpoints.items.len) : (j += 1) {
            const endpoint_name = endpoints.items[j];
            var endpoint_idx: usize = undefined;
            var found_endpoint = false;

            var k: usize = 0;
            while (k < graph.sorted_nodes.items.len) : (k += 1) {
                const node_idx = graph.sorted_nodes.items[k];
                const node_name = graph.nodes.items[node_idx].name;
                if (std.mem.eql(u8, endpoint_name, node_name)) {
                    endpoint_idx = k;
                    found_endpoint = true;
                    break;
                }
            }
            try std.testing.expect(found_endpoint);

            try std.testing.expect(source_idx < endpoint_idx);
        }
    }
}

// Node1 --> Node3 --> Node2
test "rendergraph-compile-topology-1" {
    const topo_json =
        \\[
        \\  {
        \\    "name": "Node0",
        \\    "inputs": [],
        \\    "outputs": ["0"]
        \\  },
        \\  {
        \\    "name": "Node1",
        \\    "inputs": ["0"],
        \\    "outputs": ["1"]
        \\  },
        \\  {
        \\    "name": "Node2",
        \\    "inputs": ["1"],
        \\    "outputs": []
        \\  }
        \\]
    ;

    try topology_test_helper(topo_json);
}

// 1 2
//   │
//  ┌┴┐
//  ▼ ▼
//  3 4
//    │
//   ┌┴┐
//   ▼ ▼
//   5 6
//   │ │
//   └┬┘
//    │
//    ▼
//    7
test "rendergraph-compile-topology-2" {
    const topo_json =
        \\[
        \\  {
        \\    "name": "Node3",
        \\    "inputs": ["0"],
        \\    "outputs": []
        \\  },
        \\  {
        \\    "name": "Node7",
        \\    "inputs": ["3", "4"],
        \\    "outputs": []
        \\  },
        \\  {
        \\    "name": "Node1",
        \\    "inputs": [],
        \\    "outputs": []
        \\  },
        \\  {
        \\    "name": "Node2",
        \\    "inputs": [],
        \\    "outputs": ["0", "1"]
        \\  },
        \\  {
        \\    "name": "Node4",
        \\    "inputs": ["1"],
        \\    "outputs": ["2"]
        \\  },
        \\  {
        \\    "name": "Node5",
        \\    "inputs": ["2"],
        \\    "outputs": ["3"]
        \\  },
        \\  {
        \\    "name": "Node6",
        \\    "inputs": ["2"],
        \\    "outputs": ["4"]
        \\  }
        \\]
    ;

    try topology_test_helper(topo_json);
}

// 1 -> 2
test "rendergraph-compile-topology-3" {
    const topo_json =
        \\[
        \\  {
        \\    "name": "Node1",
        \\    "inputs": [],
        \\    "outputs": ["1"]
        \\  },
        \\  {
        \\    "name": "Node2",
        \\    "inputs": ["1"],
        \\    "outputs": ["0"]
        \\  }
        \\]
    ;

    try topology_test_helper(topo_json);
}
