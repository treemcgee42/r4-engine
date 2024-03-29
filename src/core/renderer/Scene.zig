const std = @import("std");
const dutil = @import("debug_utils");
const r4_ecs = @import("ecs");
const math = @import("math");
const PipelineHandle = @import("./Renderer.zig").PipelineHandle;
const Renderer = @import("./Renderer.zig");
const l0vk = @import("./layer0/vulkan/vulkan.zig");
const vulkan = @import("vulkan");

// ---

pub const SceneError = error{
    object_missing_transform,
};

// ---

_renderer: *Renderer,

mesh_system: MeshSystem,
material_system: MaterialSystem,

objects: std.ArrayList(Object),
objects_ecs: r4_ecs.Ecs,
camera: Camera,

frame_number: usize = 0,

// ---

const Self = @This();

pub fn init(allocator: std.mem.Allocator, renderer: *Renderer) !Self {
    const mesh_system = try MeshSystem.init(renderer);
    const material_system = MaterialSystem.init(allocator);

    var ecs = r4_ecs.Ecs.init(allocator);
    try ecs.register_component(MeshSystem.Mesh);
    try ecs.register_component(MaterialHandle);
    try ecs.register_component(Transform);
    try ecs.register_component(Translation);
    try ecs.register_component(Scale);

    dutil.log("scene", .info, "scene initialized", .{});

    return .{
        ._renderer = renderer,

        .mesh_system = mesh_system,
        .material_system = material_system,

        .objects = std.ArrayList(Object).init(allocator),
        .objects_ecs = ecs,
        .camera = Camera.init(
            math.Vec3f.init(0, 0, -5),
            math.Vec3f.init(0, 0, 0),
            math.Vec3f.init(0, 1, 0),
        ),
    };
}

pub fn deinit(self: *Self) void {
    self.camera.deinit();
    self.mesh_system.deinit();
    self.material_system.deinit();
    self.objects.deinit();
    self.objects_ecs.deinit();
}

pub fn deinit_generic(self_: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(self_));
    var allocator = self._renderer.allocator;
    self.deinit();
    allocator.destroy(self);
}

pub fn create_object(self: *Self, name: [*c]const u8) !r4_ecs.Entity {
    const entity = self.objects_ecs.create_entity();
    try self.objects.append(.{ .entity = entity, .name = name });

    const default_transform = Transform{
        .val = math.Mat4f.init_identity(),
    };
    try self.objects_ecs.add_component_for_entity(entity, default_transform);
    const default_translation = Translation{
        .val = math.Vec3f.init(0, 0, 0),
    };
    try self.objects_ecs.add_component_for_entity(entity, default_translation);
    const default_scale = Scale{
        .val = math.Vec3f.init(1, 1, 1),
    };
    try self.objects_ecs.add_component_for_entity(entity, default_scale);

    return entity;
}

pub fn assign_mesh_to_object(self: *Self, object: r4_ecs.Entity, mesh: MeshSystem.Mesh) !void {
    try self.objects_ecs.add_component_for_entity(object, mesh);
}

pub fn assign_material_to_object(
    self: *Self,
    object: r4_ecs.Entity,
    material: MaterialHandle,
) !void {
    try self.objects_ecs.add_component_for_entity(object, material);
}

pub fn update_transform_of_object(
    self: *Self,
    object: r4_ecs.Entity,
    transform: Transform,
) !void {
    try self.objects_ecs.add_component_for_entity(object, transform);
}

/// Reconstructs the transform from scratch from the following components, in order:
/// - Translation
/// (- Rotation, when added)
/// - Scale
fn update_entity_transform_from_components(self: *Self, entity: r4_ecs.Entity) !void {
    var new_transform_val = math.Mat4f.init_identity();

    const translation_ptr = self.objects_ecs.get_component_for_entity(entity, Translation);
    new_transform_val.apply_translation(&translation_ptr.?.val);

    const scale_ptr = self.objects_ecs.get_component_for_entity(entity, Scale);
    new_transform_val.apply_scale(&scale_ptr.?.val);

    try self.objects_ecs.add_component_for_entity(entity, Transform{ .val = new_transform_val });
}

pub fn update_translation_of_object(
    self: *Self,
    object: r4_ecs.Entity,
    translation: Translation,
) !void {
    try self.objects_ecs.add_component_for_entity(object, translation);
    try self.update_entity_transform_from_components(object);
}

pub fn update_scale_of_object(
    self: *Self,
    object: r4_ecs.Entity,
    scale: Scale,
) !void {
    try self.objects_ecs.add_component_for_entity(object, scale);
    try self.update_entity_transform_from_components(object);
}

pub fn draw(self: *Self, command_buffer: l0vk.VkCommandBuffer) !void {
    self.frame_number += 1;

    var prev_material: ?MaterialHandle = null;

    var i: usize = 0;
    while (i < self.objects.items.len) : (i += 1) {
        const object = self.objects.items[i].entity;

        const mesh = self.objects_ecs.get_component_for_entity(
            object,
            MeshSystem.Mesh,
        ) orelse {
            dutil.log(
                "scene",
                .warn,
                "object {} is missing mesh",
                .{object},
            );
            continue;
        };
        const material = self.objects_ecs.get_component_for_entity(
            object,
            MaterialHandle,
        ) orelse {
            dutil.log(
                "scene",
                .warn,
                "object {} is missing material",
                .{object},
            );
            continue;
        };
        const transform = self.objects_ecs.get_component_for_entity(
            object,
            Transform,
        ) orelse {
            dutil.log(
                "scene",
                .warn,
                "object {} is missing transform",
                .{object},
            );
            continue;
        };

        if (material.* != prev_material) {
            self.material_system.bind(command_buffer, material.*);
            prev_material = material.*;
        }

        var view_matrix = self.camera.view_matrix;
        var projection_matrix = self.camera.projection_matrix;
        projection_matrix.raw[1][1] *= -1;
        var transform_matrix = transform.val;
        var rotate_axis = math.Vec3f.init(0, 1, 0);
        transform_matrix.apply_rotation(
            @as(f32, @floatFromInt(self.frame_number)) * 0.01,
            &rotate_axis,
        );
        var intermediate = math.mat4f_times_mat4f(&view_matrix, &transform_matrix);
        const mvp_matrix = math.mat4f_times_mat4f(&projection_matrix, &intermediate);
        var push_constants = PushConstants{
            .data = undefined,
            .transform_matrix = mvp_matrix,
        };
        self.material_system.upload_push_constants(
            command_buffer,
            material.*,
            &push_constants,
        );

        var bufs = [_]vulkan.VkBuffer{mesh.vertex_buffer.buffer};
        var offsets = [_]vulkan.VkDeviceSize{0};
        vulkan.vkCmdBindVertexBuffers(
            command_buffer,
            0,
            1,
            bufs[0..].ptr,
            offsets[0..].ptr,
        );

        vulkan.vkCmdDraw(
            command_buffer,
            @intCast(mesh.vertices.items.len),
            1,
            0,
            0,
        );
    }
}

// ---

const tm42_camera = @import("tm42_camera");

pub const Camera = struct {
    look_from: math.Vec3f,
    look_at: math.Vec3f,
    up_direction: math.Vec3f,

    view_matrix: math.Mat4f,
    projection_matrix: math.Mat4f,

    t_camera: *tm42_camera.Tm42TurntableCamera,

    pub fn init(
        look_from: math.Vec3f,
        look_at: math.Vec3f,
        up_direction: math.Vec3f,
    ) Camera {
        // var look_from_ = look_from;
        // var look_at_ = look_at;
        // var up_direction_ = up_direction;

        // ---

        const look_at_cast: [*c]f32 = @constCast(&look_at.raw[0]);
        const look_from_cast: [*c]f32 = @constCast(&look_from.raw[0]);
        const tm42_create_info = tm42_camera.Tm42CameraCreateInfo{
            .look_at = look_at_cast,
            .look_from = look_from_cast,
            .vertical_fov = 60,
            .aspect_ratio = 1.33,
            .z_near = 0.1,
            .z_far = -1,
        };

        const t_camera = tm42_camera.tm42_create_turntable_camera(tm42_create_info);

        const view_matrix = math.Mat4f.init_from_c_array(tm42_camera.tm42_turntable_camera_get_view_matrix(t_camera));
        const proj_matrix = math.Mat4f.init_from_c_array(tm42_camera.tm42_turntable_camera_get_projection_matrix(t_camera));

        // ---

        return .{
            .look_from = look_from,
            .look_at = look_at,
            .up_direction = up_direction,

            // .view_matrix = math.Mat4f.init_look_at(&look_from_, &look_at_, &up_direction_),
            .view_matrix = view_matrix,
            // .projection_matrix = math.Mat4f.init_perspective(70.0, 1700 / 900, 0.1, 200),
            .projection_matrix = proj_matrix,

            .t_camera = t_camera,
        };
    }

    pub fn deinit(self: *Camera) void {
        tm42_camera.tm42_destroy_turntable_camera(self.t_camera);
    }
};

// ---

pub const PushConstants = struct {
    data: math.Vec4f,
    transform_matrix: math.Mat4f,
};

// ---

const cglm = @import("cglm");

const VertexRaw = extern struct {
    position: cglm.vec3,
    normal: cglm.vec3,
    color: cglm.vec3,
};

pub const Vertex = extern struct {
    position: math.Vec3f,
    normal: math.Vec3f,
    color: math.Vec3f,
};

comptime {
    std.debug.assert(@offsetOf(Vertex, "position") == @offsetOf(VertexRaw, "position"));
    std.debug.assert(@offsetOf(Vertex, "normal") == @offsetOf(VertexRaw, "normal"));
    std.debug.assert(@offsetOf(Vertex, "color") == @offsetOf(VertexRaw, "color"));
}

pub const MeshSystem = @import("vulkan/mesh.zig").MeshSystem(Vertex);

// ---

pub const Material = struct {
    pipeline: l0vk.VkPipeline,
    pipeline_layout: l0vk.VkPipelineLayout,

    pub fn bind(self: Material, command_buffer: l0vk.VkCommandBuffer) void {
        vulkan.vkCmdBindPipeline(
            command_buffer,
            vulkan.VK_PIPELINE_BIND_POINT_GRAPHICS,
            self.pipeline,
        );
    }

    pub fn upload_push_constants(
        self: Material,
        command_buffer: l0vk.VkCommandBuffer,
        push_constants: *PushConstants,
    ) void {
        vulkan.vkCmdPushConstants(
            command_buffer,
            self.pipeline_layout,
            vulkan.VK_SHADER_STAGE_VERTEX_BIT,
            0,
            @sizeOf(PushConstants),
            push_constants,
        );
    }
};

pub const MaterialHandle = usize;

pub const MaterialSystem = struct {
    materials: std.ArrayList(Material),

    pub fn init(allocator: std.mem.Allocator) MaterialSystem {
        return .{
            .materials = std.ArrayList(Material).init(allocator),
        };
    }

    pub fn deinit(self: *MaterialSystem) void {
        self.materials.deinit();
    }

    pub fn register_material(self: *MaterialSystem, material: Material) !MaterialHandle {
        try self.materials.append(material);
        return self.materials.items.len - 1;
    }

    fn bind(
        self: *MaterialSystem,
        command_buffer: l0vk.VkCommandBuffer,
        handle: MaterialHandle,
    ) void {
        self.materials.items[handle].bind(command_buffer);
    }

    fn upload_push_constants(
        self: *MaterialSystem,
        command_buffer: l0vk.VkCommandBuffer,
        handle: MaterialHandle,
        push_constants: *PushConstants,
    ) void {
        self.materials.items[handle].upload_push_constants(
            command_buffer,
            push_constants,
        );
    }
};

// ---

pub const Transform = struct {
    val: math.Mat4f,
};
pub const Translation = struct {
    val: math.Vec3f,
};
pub const Scale = struct {
    val: math.Vec3f,
};

// ---

pub const Object = struct {
    entity: r4_ecs.Entity,
    name: [*c]const u8,
};
