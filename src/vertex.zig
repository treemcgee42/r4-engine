const Math = @import("math.zig");
const vulkan = @import("c.zig").vulkan;

pub const Vertex = struct {
    position: Math.Vec2f,
    color: Math.Vec3f,

    pub fn get_binding_description() vulkan.VkVertexInputBindingDescription {
        return .{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .inputRate = vulkan.VK_VERTEX_INPUT_RATE_VERTEX,
        };
    }

    pub fn get_attribute_descriptions() [2]vulkan.VkVertexInputAttributeDescription {
        return [2]vulkan.VkVertexInputAttributeDescription{
            .{
                .binding = 0,
                .location = 0,
                .format = vulkan.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(Vertex, "position"),
            },
            .{
                .binding = 0,
                .location = 1,
                .format = vulkan.VK_FORMAT_R32G32B32_SFLOAT,
                .offset = @offsetOf(Vertex, "color"),
            },
        };
    }
};

pub const vertices = [_]Vertex{
    Vertex{
        .position = Math.Vec2f.init(-0.5, -0.5),
        .color = Math.Vec3f.init(1.0, 0.0, 1.0),
    },
    Vertex{
        .position = Math.Vec2f.init(0.5, -0.5),
        .color = Math.Vec3f.init(0.0, 1.0, 0.0),
    },
    Vertex{
        .position = Math.Vec2f.init(0.5, 0.5),
        .color = Math.Vec3f.init(0.0, 0.0, 1.0),
    },
    Vertex{
        .position = Math.Vec2f.init(-0.5, 0.5),
        .color = Math.Vec3f.init(1.0, 1.0, 1.0),
    },
};

pub const indices = [_]u16{ 0, 1, 2, 2, 3, 0 };
