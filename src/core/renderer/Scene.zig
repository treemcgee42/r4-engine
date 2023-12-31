const std = @import("std");
const dutil = @import("debug_utils");
const r4_ecs = @import("ecs");
const math = @import("../../math.zig");
const PipelineHandle = @import("./Renderer.zig").PipelineHandle;
const Renderer = @import("./Renderer.zig");
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

    const default_transform: Transform = math.Mat4f.init_identity();
    try self.objects_ecs.add_component_for_entity(entity, default_transform);
    const default_translation: Translation = math.Vec3f.init(0, 0, 0);
    try self.objects_ecs.add_component_for_entity(entity, default_translation);

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
fn update_entity_transform_from_components(self: *Self, entity: r4_ecs.Entity) !void {
    var new_transform: Transform = math.Mat4f.init_identity();

    const translation_ptr = self.objects_ecs.get_component_for_entity(entity, Translation);
    new_transform.apply_translation(translation_ptr.?);

    try self.objects_ecs.add_component_for_entity(entity, new_transform);
}

pub fn update_translation_of_object(
    self: *Self,
    object: r4_ecs.Entity,
    translation: Translation,
) !void {
    try self.objects_ecs.add_component_for_entity(object, translation);
    try self.update_entity_transform_from_components(object);
}

pub fn draw(self: *Self) !void {
    self.frame_number += 1;

    var prev_material: ?MaterialHandle = null;

    var i: usize = 0;
    while (i < self.objects.items.len) : (i += 1) {
        const object = self.objects.items[i].entity;

        const mesh = self.objects_ecs.get_component_for_entity(object, MeshSystem.Mesh) orelse {
            dutil.log(
                "scene",
                .warn,
                "object {} is missing mesh",
                .{object},
            );
            continue;
        };
        const material = self.objects_ecs.get_component_for_entity(object, MaterialHandle) orelse {
            dutil.log(
                "scene",
                .warn,
                "object {} is missing material",
                .{object},
            );
            continue;
        };
        const transform = self.objects_ecs.get_component_for_entity(object, Transform) orelse {
            dutil.log(
                "scene",
                .warn,
                "object {} is missing transform",
                .{object},
            );
            continue;
        };

        if (material.* != prev_material) {
            try self.bind_material(material.*);
            prev_material = material.*;
        }

        var view_matrix = self.camera.view_matrix;
        var projection_matrix = self.camera.projection_matrix;
        var transform_matrix = transform.*;
        var rotate_axis = math.Vec3f.init(0, 1, 0);
        transform_matrix.apply_rotation(@as(f32, @floatFromInt(self.frame_number)) * 0.01, &rotate_axis);
        var intermediate = math.mat4f_times_mat4f(&view_matrix, &transform_matrix);
        const mvp_matrix = math.mat4f_times_mat4f(&projection_matrix, &intermediate);
        const push_constants = PushConstants{
            .data = undefined,
            .transform_matrix = mvp_matrix,
        };
        const pipeline_handle = self.material_system.materials.items[material.*].pipeline;
        try self._renderer.upload_push_constants(pipeline_handle, push_constants);

        try self._renderer.bind_vertex_buffer(mesh.vertex_buffer.buffer);

        try self._renderer.draw(mesh.vertices.items.len);
    }
}

// ---

pub const Camera = struct {
    look_from: math.Vec3f,
    look_at: math.Vec3f,
    up_direction: math.Vec3f,

    view_matrix: math.Mat4f,
    projection_matrix: math.Mat4f,

    pub fn init(look_from: math.Vec3f, look_at: math.Vec3f, up_direction: math.Vec3f) Camera {
        var look_from_ = look_from;
        var look_at_ = look_at;
        var up_direction_ = up_direction;

        return .{
            .look_from = look_from,
            .look_at = look_at,
            .up_direction = up_direction,

            .view_matrix = math.Mat4f.init_look_at(&look_from_, &look_at_, &up_direction_),
            .projection_matrix = math.Mat4f.init_perspective(70.0, 1700 / 900, 0.1, 200),
        };
    }
};

// ---

pub const PushConstants = struct {
    data: math.Vec4f,
    transform_matrix: math.Mat4f,
};

// ---

const cglm = @import("../../c.zig").cglm;

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
    pipeline: PipelineHandle,

    pub fn bind(self: Material, renderer: *Renderer) void {
        renderer.bind_pipeline(self.pipeline);
    }
};

pub const MaterialHandle = usize;

pub fn bind_material(self: *Self, material: MaterialHandle) !void {
    try self._renderer.bind_pipeline(material);
}

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
};

// ---

pub const Transform = math.Mat4f;
pub const Translation = math.Vec3f;

// ---

pub const Object = struct {
    entity: r4_ecs.Entity,
    name: [*c]const u8,
};
