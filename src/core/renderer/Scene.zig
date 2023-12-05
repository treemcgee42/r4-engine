const std = @import("std");
const math = @import("../../math.zig");
const PipelineHandle = @import("./Renderer.zig").PipelineHandle;
const Renderer = @import("./Renderer.zig");
const vulkan = @import("vulkan");

// ---

_renderer: *Renderer,

mesh_system: MeshSystem,
material_system: MaterialSystem,

objects: std.ArrayList(Object),
camera: Camera,

// ---

const Self = @This();

pub fn init(allocator: std.mem.Allocator, renderer: *Renderer) !Self {
    const mesh_system = try MeshSystem.init(renderer);
    const material_system = MaterialSystem.init(allocator);

    return .{
        ._renderer = renderer,

        .mesh_system = mesh_system,
        .material_system = material_system,

        .objects = std.ArrayList(Object).init(allocator),
        .camera = Camera.init(
            math.Vec3f.init(0, -6, -10),
            math.Vec3f.init(0, 0, 0),
            math.Vec3f.init(0, 1, 0),
        ),
    };
}

pub fn deinit(self: *Self) void {
    self.mesh_system.deinit();
    self.material_system.deinit();
    self.objects.deinit();
}

pub fn draw(self: *Self) !void {
    var prev_material: ?MaterialHandle = null;

    var i: usize = 0;
    while (i < self.objects.items.len) : (i += 1) {
        const object = self.objects.items[i];

        if (object.material != prev_material) {
            try self.bind_material(object.material);
            prev_material = object.material;
        }

        // var view_matrix = self.camera.view_matrix;
        // var projection_matrix = self.camera.projection_matrix;
        // var transform_matrix = object.transform_matrix;
        // var intermediate = math.mat4f_times_mat4f(&view_matrix, &transform_matrix);
        // const mvp_matrix = math.mat4f_times_mat4f(&projection_matrix, &intermediate);
        // const push_constants = PushConstants{
        //     .data = undefined,
        //     .transform_matrix = mvp_matrix,
        // };
        // const pipeline_handle = self.material_system.materials.items[object.material].pipeline;
        // try self._renderer.upload_push_constants(pipeline_handle, push_constants);

        var buffers = [_]vulkan.VkBuffer{object.mesh.vertex_buffer.buffer};
        try self._renderer.bind_vertex_buffers(&buffers);

        try self._renderer.draw(object.mesh.vertices.items.len);
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

pub const Vertex = struct {
    position: math.Vec3f,
    normal: math.Vec3f,
    color: math.Vec3f,
};

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

pub const Object = struct {
    mesh: MeshSystem.Mesh,
    material: MaterialHandle,
    transform_matrix: math.Mat4f,
};
