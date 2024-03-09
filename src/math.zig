const std = @import("std");
const cglm = @import("cglm");

pub const Vec2f = extern struct {
    raw: cglm.vec2,

    pub fn init(x: f32, y: f32) Vec2f {
        return .{
            .raw = [_]f32{ x, y },
        };
    }

    pub fn hash(self: Vec2f) u64 {
        return @as(u64, @intFromFloat(self.raw[0])) ^ (@as(u64, @intFromFloat(self.raw[1])) << 1);
    }

    pub fn eql(self: Vec2f, other: Vec2f) bool {
        return self.raw[0] == other.raw[0] and self.raw[1] == other.raw[1];
    }
};

pub const Vec3f = extern struct {
    raw: cglm.vec3,

    pub fn init(x: f32, y: f32, z: f32) Vec3f {
        return .{
            .raw = [_]f32{ x, y, z },
        };
    }

    pub fn hash(self: Vec3f) u64 {
        return @as(u64, @intFromFloat(self.raw[0])) ^ (@as(u64, @intFromFloat(self.raw[1])) << 1) ^ (@as(u64, @intFromFloat(self.raw[2])) << 2);
    }

    pub fn eql(self: Vec3f, other: Vec3f) bool {
        return self.raw[0] == other.raw[0] and self.raw[1] == other.raw[1] and self.raw[2] == other.raw[2];
    }

    comptime {
        std.debug.assert(@sizeOf(Vec3f) == @sizeOf(cglm.vec3));
        std.debug.assert(@alignOf(Vec3f) == @alignOf(cglm.vec3));
    }
};

pub const Vec4f = extern struct {
    raw: cglm.vec4,

    pub fn init(x: f32, y: f32, z: f32, w: f32) Vec4f {
        return .{
            .raw = [_]f32{ x, y, z, w },
        };
    }
};

pub const Mat4f = extern struct {
    raw: cglm.mat4,

    pub fn init_with_cols(x: Vec4f, y: Vec4f, z: Vec4f, w: Vec4f) Mat4f {
        return .{
            .raw = [_][4]f32{ x.raw, y.raw, z.raw, w.raw },
        };
    }

    pub fn init_from_c_array(arr: [*c]f32) Mat4f {
        var zigMatrix: [4][4]f32 = undefined;

        // Loop through the columns
        var col: usize = 0;
        while (col < 4) : (col += 1) {
            // Loop through the rows
            var row: usize = 0;
            while (row < 4) : (row += 1) {
                // Copy from the one-dimensional C array to the two-dimensional Zig array.
                // Note: In column-major storage, index = column * NUM_ROWS + row
                zigMatrix[col][row] = arr[col * 4 + row];
            }
        }

        return Mat4f{
            .raw = zigMatrix,
        };
    }

    pub fn init_identity() Mat4f {
        return init_with_cols(
            Vec4f.init(1.0, 0.0, 0.0, 0.0),
            Vec4f.init(0.0, 1.0, 0.0, 0.0),
            Vec4f.init(0.0, 0.0, 1.0, 0.0),
            Vec4f.init(0.0, 0.0, 0.0, 1.0),
        );
    }

    pub fn init_translate(translation: *Vec3f) Mat4f {
        var to_return = init_identity();
        cglm.glmc_translate(&to_return.raw, translation.raw[0..].ptr);

        return to_return;
    }

    pub fn init_look_at(eye: *Vec3f, target: *Vec3f, up: *Vec3f) Mat4f {
        var raw: cglm.mat4 = undefined;
        cglm.glmc_lookat(eye.raw[0..].ptr, target.raw[0..].ptr, up.raw[0..].ptr, &raw);
        return .{
            .raw = raw,
        };
    }

    pub fn init_perspective(fov_y: f32, aspect: f32, near: f32, far: f32) Mat4f {
        var raw: cglm.mat4 = undefined;
        cglm.glmc_perspective(fov_y, aspect, near, far, &raw);
        return .{
            .raw = raw,
        };
    }

    pub fn apply_rotation(self: *Mat4f, angle: f32, axis: *Vec3f) void {
        cglm.glmc_rotate(self.raw[0..].ptr, angle, axis.raw[0..].ptr);
    }

    pub fn apply_translation(self: *Mat4f, translation: *const Vec3f) void {
        // TODO: shouldn't need to do this.
        var translation_copy: Vec3f = translation.*;
        cglm.glmc_translate(self.raw[0..].ptr, translation_copy.raw[0..].ptr);
    }

    pub fn apply_scale(self: *Mat4f, scale: *const Vec3f) void {
        // TODO: shouldn't need to do this.
        var scale_copy: Vec3f = scale.*;
        cglm.glmc_scale(self.raw[0..].ptr, scale_copy.raw[0..].ptr);
    }

    comptime {
        std.debug.assert(@sizeOf(Mat4f) == @sizeOf(cglm.mat4));
        std.debug.assert(@alignOf(Mat4f) == @alignOf(cglm.mat4));
    }
};

pub fn mat4f_times_mat4f(a: *Mat4f, b: *Mat4f) Mat4f {
    var raw: cglm.mat4 = undefined;
    cglm.glmc_mat4_mul(&a.raw, &b.raw, &raw);

    return .{
        .raw = raw,
    };
}
