const math = @import("math");
const vulkan = @import("c.zig").vulkan;

pub const Vertex = struct {
    position: math.Vec3f,
    color: math.Vec3f,
    tex_coord: math.Vec2f,

    pub fn get_binding_description() vulkan.VkVertexInputBindingDescription {
        return .{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .inputRate = vulkan.VK_VERTEX_INPUT_RATE_VERTEX,
        };
    }

    pub fn get_attribute_descriptions() [3]vulkan.VkVertexInputAttributeDescription {
        return [3]vulkan.VkVertexInputAttributeDescription{
            .{
                .binding = 0,
                .location = 0,
                .format = vulkan.VK_FORMAT_R32G32B32_SFLOAT,
                .offset = @offsetOf(Vertex, "position"),
            },
            .{
                .binding = 0,
                .location = 1,
                .format = vulkan.VK_FORMAT_R32G32B32_SFLOAT,
                .offset = @offsetOf(Vertex, "color"),
            },
            .{
                .binding = 0,
                .location = 2,
                .format = vulkan.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(Vertex, "tex_coord"),
            },
        };
    }

    pub fn hash(self: Vertex) u64 {
        return ((self.position.hash()) ^ (self.color.hash() << 1) >> 1) ^ (self.tex_coord.hash() << 1);
    }

    pub fn eql(self: Vertex, other: Vertex) bool {
        return self.position.eql(other.position) and self.color.eql(other.color) and self.tex_coord.eql(other.tex_coord);
    }
};

// pub const vertices = [_]Vertex{
//     Vertex{
//         .position = math.Vec3f.init(-0.5, -0.5, 0.0),
//         .color = math.Vec3f.init(1.0, 0.0, 1.0),
//         .tex_coord = math.Vec2f.init(1.0, 0.0),
//     },
//     Vertex{
//         .position = math.Vec3f.init(0.5, -0.5, 0.0),
//         .color = math.Vec3f.init(0.0, 1.0, 0.0),
//         .tex_coord = math.Vec2f.init(0.0, 0.0),
//     },
//     Vertex{
//         .position = math.Vec3f.init(0.5, 0.5, 0.0),
//         .color = math.Vec3f.init(0.0, 0.0, 1.0),
//         .tex_coord = math.Vec2f.init(0.0, 1.0),
//     },
//     Vertex{
//         .position = math.Vec3f.init(-0.5, 0.5, 0.0),
//         .color = math.Vec3f.init(1.0, 1.0, 1.0),
//         .tex_coord = math.Vec2f.init(1.0, 1.0),
//     },
//
//     Vertex{
//         .position = math.Vec3f.init(-0.5, -0.5, -0.5),
//         .color = math.Vec3f.init(1.0, 0.0, 1.0),
//         .tex_coord = math.Vec2f.init(1.0, 0.0),
//     },
//     Vertex{
//         .position = math.Vec3f.init(0.5, -0.5, -0.5),
//         .color = math.Vec3f.init(0.0, 1.0, 0.0),
//         .tex_coord = math.Vec2f.init(0.0, 0.0),
//     },
//     Vertex{
//         .position = math.Vec3f.init(0.5, 0.5, -0.5),
//         .color = math.Vec3f.init(0.0, 0.0, 1.0),
//         .tex_coord = math.Vec2f.init(0.0, 1.0),
//     },
//     Vertex{
//         .position = math.Vec3f.init(-0.5, 0.5, -0.5),
//         .color = math.Vec3f.init(1.0, 1.0, 1.0),
//         .tex_coord = math.Vec2f.init(1.0, 1.0),
//     },
// };
//
// pub const indices = [_]u16{
//     0, 1, 2, 2, 3, 0, 4, //
//     5, 6, 6, 7, 4,
// };

pub const UniformBufferObject = struct {
    model: math.Mat4f,
    view: math.Mat4f,
    proj: math.Mat4f,
};
