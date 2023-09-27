const cglm = @import("c.zig").cglm;

pub const Vec2f = struct {
    raw: cglm.vec2,

    pub fn init(x: f32, y: f32) Vec2f {
        return .{
            .raw = [_]f32{ x, y },
        };
    }
};

pub const Vec3f = struct {
    raw: cglm.vec3,

    pub fn init(x: f32, y: f32, z: f32) Vec3f {
        return .{
            .raw = [_]f32{ x, y, z },
        };
    }
};
