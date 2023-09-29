const std = @import("std");
const vulkan = @import("../c.zig").vulkan;
const fast_obj = @import("../c.zig").fast_obj;
const buffer = @import("./buffer.zig");
const Vertex = @import("../vertex.zig").Vertex;
const VulkanError = @import("./vulkan.zig").VulkanError;
const math = @import("../math.zig");

const model_path = "models/viking_room.obj";
const texture_path = "textures/viking_room.png";

allocator: std.mem.Allocator,

texture: buffer.TextureImage,

vertices: []const Vertex,
vertex_buffer: buffer.VertexBuffer,
indices: []const u32,
index_buffer: buffer.IndexBuffer,

const Model = @This();

pub fn init(
    allocator: std.mem.Allocator,
    physical_device: vulkan.VkPhysicalDevice,
    logical_device: vulkan.VkDevice,
    command_pool: vulkan.VkCommandPool,
    graphics_queue: vulkan.VkQueue,
) VulkanError!Model {
    const texture_image = try buffer.TextureImage.init(
        physical_device,
        logical_device,
        command_pool,
        graphics_queue,
        texture_path,
    );

    const vertices_indices = try load_obj(allocator, model_path);

    const vertex_buffer = try buffer.VertexBuffer.init(
        physical_device,
        logical_device,
        command_pool,
        graphics_queue,
        vertices_indices.vertices,
    );

    const index_buffer = try buffer.IndexBuffer.init(
        physical_device,
        logical_device,
        command_pool,
        graphics_queue,
        vertices_indices.indices,
    );

    return .{
        .allocator = allocator,

        .texture = texture_image,

        .vertices = vertices_indices.vertices,
        .vertex_buffer = vertex_buffer,
        .indices = vertices_indices.indices,
        .index_buffer = index_buffer,
    };
}

pub fn deinit(self: Model, device: vulkan.VkDevice) void {
    self.texture.deinit(device);

    self.vertex_buffer.deinit(device);
    self.index_buffer.deinit(device);

    self.allocator.free(self.vertices);
    self.allocator.free(self.indices);
}

const LoadObjReturnType = struct {
    vertices: []Vertex,
    indices: []u32,
};

fn load_obj(
    allocator: std.mem.Allocator,
    filename: [*c]const u8,
) VulkanError!LoadObjReturnType {
    var fast_obj_mesh_ptr = fast_obj.fast_obj_read(filename);
    if (fast_obj_mesh_ptr == null) {
        return VulkanError.model_loading_failed;
    }
    var fast_obj_mesh = fast_obj_mesh_ptr.*;

    var vertices = try allocator.alloc(Vertex, fast_obj_mesh.face_count * 3);
    var num_vertices: usize = 0;
    var indices = try allocator.alloc(u32, fast_obj_mesh.face_count * 3);
    var num_indices: usize = 0;

    const HashmapCtx = struct {
        const HashmapCtx = @This();

        pub fn hash(self: HashmapCtx, key: Vertex) u64 {
            _ = self;
            return key.hash();
        }

        pub fn eql(self: HashmapCtx, lhs: Vertex, rhs: Vertex) bool {
            _ = self;
            return lhs.eql(rhs);
        }
    };
    const CustomHashMap = std.HashMap(Vertex, u32, HashmapCtx, std.hash_map.default_max_load_percentage);
    var unique_vertices = CustomHashMap.init(allocator);
    defer unique_vertices.deinit();

    var face_idx: usize = 0;
    while (face_idx < fast_obj_mesh.face_count) : (face_idx += 1) {
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            const fast_obj_index = fast_obj_mesh.indices[face_idx * 3 + i];

            const v = Vertex{
                .position = math.Vec3f.init(
                    fast_obj_mesh.positions[3 * fast_obj_index.p + 0],
                    fast_obj_mesh.positions[3 * fast_obj_index.p + 1],
                    fast_obj_mesh.positions[3 * fast_obj_index.p + 2],
                ),
                .tex_coord = math.Vec2f.init(
                    fast_obj_mesh.texcoords[2 * fast_obj_index.t + 0],
                    1.0 - fast_obj_mesh.texcoords[2 * fast_obj_index.t + 1],
                ),
                .color = math.Vec3f.init(1.0, 1.0, 1.0),
            };

            if (unique_vertices.get(v) == null) {
                vertices[num_vertices] = v;
                try unique_vertices.put(v, @intCast(num_vertices));
                num_vertices += 1;
            }

            indices[num_indices] = unique_vertices.get(v).?;
            num_indices += 1;
        }
    }

    fast_obj.fast_obj_destroy(fast_obj_mesh_ptr);

    return LoadObjReturnType{
        .vertices = vertices,
        .indices = indices,
    };
}
