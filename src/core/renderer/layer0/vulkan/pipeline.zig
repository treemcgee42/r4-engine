const vulkan = @import("vulkan");
const l0vk = @import("./vulkan.zig");

pub const VkPipelineStageFlags = packed struct(u32) {
    top_of_pipe: bool = false,
    draw_indirect: bool = false,
    vertex_input: bool = false,
    vertex_shader: bool = false,

    tessellation_control_shader: bool = false,
    tessellation_evaluation_shader: bool = false,
    geometry_shader: bool = false,
    fragment_shader: bool = false,

    early_fragment_tests: bool = false,
    late_fragment_tests: bool = false,
    color_attachment_output: bool = false,
    compute_shader: bool = false,

    transfer: bool = false,
    bottom_of_pipe: bool = false,
    host: bool = false,
    all_graphics: bool = false,

    all_commands: bool = false,
    command_preprocess_nv: bool = false,
    conditional_rendering_ext: bool = false,
    task_shader_ext: bool = false,

    mesh_shader_ext: bool = false,
    ray_tracing_shader_khr: bool = false,
    fragment_shading_rate_attachment_khr: bool = false,
    fragment_density_process_ext: bool = false,

    transform_feedback_ext: bool = false,
    acceleration_structure_build_khr: bool = false,
    _: u2 = 0,

    _a: u4 = 0,

    pub const Bits = enum(c_uint) {
        top_of_pipe = 0x00000001,
        draw_indirect = 0x00000002,
        vertex_input = 0x00000004,
        vertex_shader = 0x00000008,

        tessellation_control_shader = 0x00000010,
        tessellation_evaluation_shader = 0x00000020,
        geometry_shader = 0x00000040,
        fragment_shader = 0x00000080,

        early_fragment_tests = 0x00000100,
        late_fragment_tests = 0x00000200,
        color_attachment_output = 0x00000400,
        compute_shader = 0x00000800,

        transfer = 0x00001000,
        bottom_of_pipe = 0x00002000,
        host = 0x00004000,
        all_graphics = 0x00008000,

        all_commands = 0x00010000,
        command_preprocess_nv = 0x00020000,
        conditional_rendering_ext = 0x00040000,
        task_shader_ext = 0x00080000,

        mesh_shader_ext = 0x00100000,
        ray_tracing_shader_khr = 0x00200000,
        fragment_shading_rate_attachment_khr = 0x00400000,
        fragment_density_process_ext = 0x00800000,

        transform_feedback_ext = 0x01000000,
        acceleration_structure_build_khr = 0x02000000,
    };
};

pub const VkQueryPipelineStatisticFlags = packed struct(u32) {
    input_assembly_vertices: bool = false,
    input_assembly_primitives: bool = false,
    vertex_shader_invocations: bool = false,
    geometry_shader_invocations: bool = false,

    geometry_shader_primitives: bool = false,
    clipping_invocations: bool = false,
    clipping_primitives: bool = false,
    fragment_shader_invocations: bool = false,

    tessellation_control_shader_patches: bool = false,
    tessellation_evaluation_shader_invocations: bool = false,
    compute_shader_invocations: bool = false,
    _: u1 = 0,

    _a: u20 = 0,

    pub const Bits = enum(c_uint) {
        input_assembly_vertices = 0x00000001,
        input_assembly_primitives = 0x00000002,
        vertex_shader_invocations = 0x00000004,
        geometry_shader_invocations = 0x00000008,

        geometry_shader_primitives = 0x00000010,
        clipping_invocations = 0x00000020,
        clipping_primitives = 0x00000040,
        fragment_shader_invocations = 0x00000080,

        tessellation_control_shader_patches = 0x00000100,
        tessellation_evaluation_shader_invocations = 0x00000200,
        compute_shader_invocations = 0x00000400,
    };
};

pub const VkPipelineBindPoint = enum(c_uint) {
    graphics = 0,
    compute = 1,
};
