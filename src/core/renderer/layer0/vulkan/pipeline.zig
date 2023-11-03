const std = @import("std");
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

// --- Pipeline layout.

pub const VkPipelineLayout = vulkan.VkPipelineLayout;
pub const VkDescriptorSetLayout = vulkan.VkDescriptorSetLayout;

pub const VkPipelineLayoutCreateFlags = packed struct(u32) {
    _: u1 = 0,
    independent_sets_ext: bool = false,

    _a: u30 = 0,

    pub const Bits = enum(c_uint) {
        independent_sets_ext = 0x00000002,
    };
};

pub const VkPushConstantRange = struct {
    stageFlags: l0vk.VkShaderStageFlags = .{},
    offset: u32,
    size: u32,

    pub fn to_vulkan_ty(self: VkPushConstantRange) vulkan.VkPushConstantRange {
        return vulkan.VkPushConstantRange{
            .stageFlags = @bitCast(self.stageFlags),
            .offset = self.offset,
            .size = self.size,
        };
    }
};

pub const VkPipelineLayoutCreateInfo = struct {
    pNext: ?*const anyopaque = null,
    flags: VkPipelineLayoutCreateFlags = .{},
    setLayouts: []VkDescriptorSetLayout = &[0]VkDescriptorSetLayout{},
    pushConstantRanges: []VkPushConstantRange = &[0]VkPushConstantRange{},

    pub fn to_vulkan_ty(self: VkPipelineLayoutCreateInfo, allocator: std.mem.Allocator) vulkan.VkPipelineLayoutCreateInfo {
        var push_constant_ranges = allocator.alloc(vulkan.VkPushConstantRange, self.pushConstantRanges.len) catch {
            @panic("fba ran out of memory");
        };
        var i: usize = 0;
        while (i < self.pushConstantRanges.len) : (i += 1) {
            push_constant_ranges[i] = self.pushConstantRanges[i].to_vulkan_ty();
        }

        return vulkan.VkPipelineLayoutCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .pNext = self.pNext,
            .setLayoutCount = @intCast(self.setLayouts.len),
            .pSetLayouts = self.setLayouts.ptr,
            .pushConstantRangeCount = @intCast(push_constant_ranges.len),
            .pPushConstantRanges = push_constant_ranges.ptr,
        };
    }
};

pub const vkCreatePipelineLayoutError = error{
    OutOfHostMemory,
    OutOfDeviceMemory,
};

pub fn vkCreatePipelineLayout(
    device: l0vk.VkDevice,
    pCreateInfo: *const VkPipelineLayoutCreateInfo,
    pAllocator: [*c]const l0vk.VkAllocationCallbacks,
) vkCreatePipelineLayoutError!VkPipelineLayout {
    var buffer: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    var pipeline_layout: VkPipelineLayout = undefined;
    var create_info = pCreateInfo.to_vulkan_ty(allocator);
    const result = vulkan.vkCreatePipelineLayout(device, &create_info, pAllocator, &pipeline_layout);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkCreatePipelineLayoutError.OutOfHostMemory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkCreatePipelineLayoutError.OutOfDeviceMemory,
            else => unreachable,
        }
    }

    return pipeline_layout;
}

pub inline fn vkDestroyPipelineLayout(
    device: l0vk.VkDevice,
    pipelineLayout: VkPipelineLayout,
    pAllocator: [*c]const l0vk.VkAllocationCallbacks,
) void {
    vulkan.vkDestroyPipelineLayout(device, pipelineLayout, pAllocator);
}

// ---

pub const VkPipeline = vulkan.VkPipeline;

pub const VkPipelineShaderStageCreateFlags = packed struct(u32) {
    allow_varying_subgroup_size_bit_ext: bool = false,
    require_full_subgroups_bit_ext: bool = false,
    _: u30 = 0,

    pub const Bits = enum(c_uint) {
        none = 0,

        allow_varying_subgroup_size_bit_ext = 0x00000001,
        require_full_subgroups_bit_ext = 0x00000002,
    };
};

pub const VkSpecializationMapEntry = struct {
    constantID: u32,
    offset: u32,
    size: usize,

    pub fn to_vulkan_ty(self: VkSpecializationMapEntry) vulkan.VkSpecializationMapEntry {
        return vulkan.VkSpecializationMapEntry{
            .constantID = self.constantID,
            .offset = self.offset,
            .size = self.size,
        };
    }
};

pub const VkSpecializationInfo = struct {
    mapEntries: []VkSpecializationMapEntry,
    dataSize: usize,
    pData: ?*const anyopaque,

    pub fn to_vulkan_ty(self: VkSpecializationInfo, allocator: std.mem.Allocator) vulkan.VkSpecializationInfo {
        var map_entries = allocator.alloc(vulkan.VkSpecializationMapEntry, self.mapEntries.len) catch {
            @panic("l0vk ran out of memory");
        };
        var i: usize = 0;
        while (i < self.mapEntries.len) : (i += 1) {
            map_entries[i] = self.mapEntries[i].to_vulkan_ty();
        }

        return vulkan.VkSpecializationInfo{
            .mapEntryCount = @intCast(map_entries.len),
            .pMapEntries = map_entries.ptr,
            .dataSize = self.dataSize,
            .pData = self.pData,
        };
    }
};

pub const VkPipelineShaderStageCreateInfo = struct {
    pNext: ?*const anyopaque = null,
    flags: VkPipelineShaderStageCreateFlags = .{},
    stage: l0vk.VkShaderStageFlags.Bits,
    module: l0vk.VkShaderModule,
    pName: [*c]const u8,
    pSpecializationInfo: ?*const VkSpecializationInfo = null,

    pub fn to_vulkan_ty(self: VkPipelineShaderStageCreateInfo, allocator: std.mem.Allocator) vulkan.VkPipelineShaderStageCreateInfo {
        var specialization_info = allocator.create(vulkan.VkSpecializationInfo) catch {
            @panic("l0vk ran out of memory");
        };
        var pSpecializationInfo: ?*const vulkan.VkSpecializationInfo = null;
        if (self.pSpecializationInfo != null) {
            specialization_info.* = self.pSpecializationInfo.?.to_vulkan_ty(allocator);
            pSpecializationInfo = specialization_info;
        }

        return vulkan.VkPipelineShaderStageCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = self.pNext,
            .flags = @bitCast(self.flags),
            .stage = @intFromEnum(self.stage),
            .module = self.module,
            .pName = self.pName,
            .pSpecializationInfo = pSpecializationInfo,
        };
    }
};

pub fn vkDestroyPipeline(
    device: l0vk.VkDevice,
    pipeline: VkPipeline,
    pAllocator: [*c]const l0vk.VkAllocationCallbacks,
) void {
    vulkan.vkDestroyPipeline(device, pipeline, pAllocator);
}

// --- Input assembly.

pub const VkVertexInputRate = enum(c_uint) {
    vertex = 0,
    instance = 1,
};

pub const VkVertexInputBindingDescription = struct {
    binding: u32,
    stride: u32,
    inputRate: VkVertexInputRate = @import("std").mem.zeroes(VkVertexInputRate),

    pub fn to_vulkan_ty(self: VkVertexInputBindingDescription) vulkan.VkVertexInputBindingDescription {
        return vulkan.VkVertexInputBindingDescription{
            .binding = self.binding,
            .stride = self.stride,
            .inputRate = @intFromEnum(self.inputRate),
        };
    }
};

pub const VkVertexInputAttributeDescription = struct {
    location: u32,
    binding: u32,
    format: l0vk.VkFormat,
    offset: u32,

    pub fn to_vulkan_ty(self: VkVertexInputAttributeDescription) vulkan.VkVertexInputAttributeDescription {
        return vulkan.VkVertexInputAttributeDescription{
            .location = self.location,
            .binding = self.binding,
            .format = @intFromEnum(self.format),
            .offset = self.offset,
        };
    }
};

pub const VkPipelineVertexInputStateCreateInfo = struct {
    pNext: ?*const anyopaque = null,
    vertex_binding_descriptions: []const VkVertexInputBindingDescription,
    vertex_attribute_descriptions: []const VkVertexInputAttributeDescription,

    pub fn to_vulkan_ty(self: VkPipelineVertexInputStateCreateInfo, allocator: std.mem.Allocator) vulkan.VkPipelineVertexInputStateCreateInfo {
        var vertex_binding_descriptions = allocator.alloc(
            vulkan.VkVertexInputBindingDescription,
            self.vertex_binding_descriptions.len,
        ) catch {
            @panic("l0vk ran out of memory");
        };
        var i: usize = 0;
        while (i < self.vertex_binding_descriptions.len) : (i += 1) {
            vertex_binding_descriptions[i] = self.vertex_binding_descriptions[i].to_vulkan_ty();
        }

        var vertex_attribute_descriptions = allocator.alloc(
            vulkan.VkVertexInputAttributeDescription,
            self.vertex_attribute_descriptions.len,
        ) catch {
            @panic("l0vk ran out of memory");
        };
        i = 0;
        while (i < self.vertex_attribute_descriptions.len) : (i += 1) {
            vertex_attribute_descriptions[i] = self.vertex_attribute_descriptions[i].to_vulkan_ty();
        }

        return vulkan.VkPipelineVertexInputStateCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .flags = 0,
            .pNext = self.pNext,
            .vertexBindingDescriptionCount = @intCast(vertex_binding_descriptions.len),
            .pVertexBindingDescriptions = vertex_binding_descriptions.ptr,
            .vertexAttributeDescriptionCount = @intCast(vertex_attribute_descriptions.len),
            .pVertexAttributeDescriptions = vertex_attribute_descriptions.ptr,
        };
    }
};

pub const VkPrimitiveTopology = enum(c_uint) {
    point_list = 0,
    line_list = 1,
    line_strip = 2,
    triangle_list = 3,
    triangle_strip = 4,
    triangle_fan = 5,
    line_list_with_adjacency = 6,
    line_strip_with_adjacency = 7,
    triangle_list_with_adjacency = 8,
    triangle_strip_with_adjacency = 9,
    patch_list = 10,
    max_enum = 2147483647,
};

pub const VkPipelineInputAssemblyStateCreateInfo = struct {
    pNext: ?*const anyopaque = null,
    topology: VkPrimitiveTopology,
    primitiveRestartEnable: bool,

    pub fn to_vulkan_ty(self: VkPipelineInputAssemblyStateCreateInfo) vulkan.VkPipelineInputAssemblyStateCreateInfo {
        return vulkan.VkPipelineInputAssemblyStateCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .flags = 0,
            .pNext = self.pNext,
            .topology = @intFromEnum(self.topology),
            .primitiveRestartEnable = if (self.primitiveRestartEnable) vulkan.VK_TRUE else vulkan.VK_FALSE,
        };
    }
};

// --- Viewport and scissor.

pub const VkDynamicState = enum(c_uint) {
    viewport = 0,
    scissor = 1,
    line_width = 2,
    depth_bias = 3,
    blend_constants = 4,
    depth_bounds = 5,
    stencil_compare_mask = 6,
    stencil_write_mask = 7,
    stencil_reference = 8,
    cull_mode = 1000267000,
    front_face = 1000267001,
    primitive_topology = 1000267002,
    viewport_with_count = 1000267003,
    scissor_with_count = 1000267004,
    vertex_input_binding_stride = 1000267005,
    depth_test_enable = 1000267006,
    depth_write_enable = 1000267007,
    depth_compare_op = 1000267008,
    depth_bounds_test_enable = 1000267009,
    stencil_test_enable = 1000267010,
    stencil_op = 1000267011,
    rasterizer_discard_enable = 1000377001,
    depth_bias_enable = 1000377002,
    primitive_restart_enable = 1000377004,
    viewport_w_scaling_nv = 1000087000,
    discard_rectangle_ext = 1000099000,
    discard_rectangle_enable_ext = 1000099001,
    discard_rectangle_mode_ext = 1000099002,
    sample_locations_ext = 1000143000,
    ray_tracing_pipeline_stack_size_khr = 1000347000,
    viewport_shading_rate_palette_nv = 1000164004,
    viewport_coarse_sample_order_nv = 1000164006,
    exclusive_scissor_enable_nv = 1000205000,
    exclusive_scissor_nv = 1000205001,
    fragment_shading_rate_khr = 1000226000,
    line_stipple_ext = 1000259000,
    vertex_input_ext = 1000352000,
    patch_control_points_ext = 1000377000,
    logic_op_ext = 1000377003,
    color_write_enable_ext = 1000381000,
    tessellation_domain_origin_ext = 1000455002,
    depth_clamp_enable_ext = 1000455003,
    polygon_mode_ext = 1000455004,
    rasterization_samples_ext = 1000455005,
    sample_mask_ext = 1000455006,
    alpha_to_coverage_enable_ext = 1000455007,
    alpha_to_one_enable_ext = 1000455008,
    logic_op_enable_ext = 1000455009,
    color_blend_enable_ext = 1000455010,
    color_blend_equation_ext = 1000455011,
    color_write_mask_ext = 1000455012,
    rasterization_stream_ext = 1000455013,
    conservative_rasterization_mode_ext = 1000455014,
    extra_primitive_overestimation_size_ext = 1000455015,
    depth_clip_enable_ext = 1000455016,
    sample_locations_enable_ext = 1000455017,
    color_blend_advanced_ext = 1000455018,
    provoking_vertex_mode_ext = 1000455019,
    line_rasterization_mode_ext = 1000455020,
    line_stipple_enable_ext = 1000455021,
    depth_clip_negative_one_to_one_ext = 1000455022,
    viewport_w_scaling_enable_nv = 1000455023,
    viewport_swizzle_nv = 1000455024,
    coverage_to_color_enable_nv = 1000455025,
    coverage_to_color_location_nv = 1000455026,
    coverage_modulation_mode_nv = 1000455027,
    coverage_modulation_table_enable_nv = 1000455028,
    coverage_modulation_table_nv = 1000455029,
    shading_rate_image_enable_nv = 1000455030,
    representative_fragment_test_enable_nv = 1000455031,
    coverage_reduction_mode_nv = 1000455032,
    attachment_feedback_loop_enable_ext = 1000524000,
    max_enum = 2147483647,
};

pub const VkPipelineDynamicStateCreateInfo = struct {
    pNext: ?*const anyopaque = null,
    dynamic_states: []const VkDynamicState,

    pub fn to_vulkan_ty(self: VkPipelineDynamicStateCreateInfo, allocator: std.mem.Allocator) vulkan.VkPipelineDynamicStateCreateInfo {
        var vk_dynamic_states = allocator.alloc(vulkan.VkDynamicState, self.dynamic_states.len) catch {
            @panic("l0vk ran out of memory");
        };
        var i: usize = 0;
        while (i < self.dynamic_states.len) : (i += 1) {
            vk_dynamic_states[i] = @intFromEnum(self.dynamic_states[i]);
        }

        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .pNext = self.pNext,
            .dynamicStateCount = @intCast(self.dynamic_states.len),
            .pDynamicStates = vk_dynamic_states.ptr,
        };
    }
};

pub const VkViewport = vulkan.VkViewport;

pub const VkPipelineViewportStateCreateInfo = struct {
    pNext: ?*const anyopaque = null,
    // Need to explicitly specify, since they can be dynamically created.
    viewportCount: u32,
    viewports: []const VkViewport,
    scissorCount: u32,
    scissors: []const l0vk.VkRect2D,

    pub fn to_vulkan_ty(self: VkPipelineViewportStateCreateInfo) vulkan.VkPipelineViewportStateCreateInfo {
        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .pNext = self.pNext,
            .viewportCount = self.viewportCount,
            .pViewports = self.viewports.ptr,
            .scissorCount = self.scissorCount,
            .pScissors = self.scissors.ptr,
            .flags = 0,
        };
    }
};

// -- Rasterizer.

pub const VkPolygonMode = enum(c_uint) {
    fill = 0,
    line = 1,
    point = 2,
    fill_rectangle_nv = 1000153000,
    max_enum = 2147483647,
};

pub const VkCullModeFlags = packed struct(u32) {
    front: bool = false,
    back: bool = false,
    _: u30 = 0,

    pub const Bits = enum(c_uint) {
        none = 0,
        front = 0x00000001,
        back = 0x00000002,
        front_and_back = 0x00000003,
    };
};

pub const VkFrontFace = enum(c_uint) {
    counter_clockwise = 0,
    clockwise = 1,
};

pub const VkPipelineRasterizationStateCreateInfo = struct {
    pNext: ?*const anyopaque = null,
    depthClampEnable: bool,
    rasterizerDiscardEnable: bool,
    polygonMode: VkPolygonMode,
    cullMode: VkCullModeFlags,
    frontFace: VkFrontFace,
    depthBiasEnable: bool,
    depthBiasConstantFactor: f32,
    depthBiasClamp: f32,
    depthBiasSlopeFactor: f32,
    lineWidth: f32,

    pub fn to_vulkan_ty(self: VkPipelineRasterizationStateCreateInfo) vulkan.VkPipelineRasterizationStateCreateInfo {
        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .pNext = self.pNext,
            .flags = 0,
            .depthClampEnable = if (self.depthClampEnable) vulkan.VK_TRUE else vulkan.VK_FALSE,
            .rasterizerDiscardEnable = if (self.rasterizerDiscardEnable) vulkan.VK_TRUE else vulkan.VK_FALSE,
            .polygonMode = @intFromEnum(self.polygonMode),
            .cullMode = @bitCast(self.cullMode),
            .frontFace = @intFromEnum(self.frontFace),
            .depthBiasEnable = if (self.depthBiasEnable) vulkan.VK_TRUE else vulkan.VK_FALSE,
            .depthBiasConstantFactor = self.depthBiasConstantFactor,
            .depthBiasClamp = self.depthBiasClamp,
            .depthBiasSlopeFactor = self.depthBiasSlopeFactor,
            .lineWidth = self.lineWidth,
        };
    }
};

// --- Multisampling.

pub const VkPipelineMultisampleStateCreateInfo = struct {
    pNext: ?*const anyopaque = null,
    rasterizationSamples: l0vk.VkSampleCountFlags.Bits,
    sampleShadingEnable: bool,
    minSampleShading: f32,
    alphaToCoverageEnable: bool,
    alphaToOneEnable: bool,

    pub fn to_vulkan_ty(self: VkPipelineMultisampleStateCreateInfo) vulkan.VkPipelineMultisampleStateCreateInfo {
        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .pNext = self.pNext,
            .flags = 0,
            .pSampleMask = null,
            .rasterizationSamples = @intFromEnum(self.rasterizationSamples),
            .sampleShadingEnable = if (self.sampleShadingEnable) vulkan.VK_TRUE else vulkan.VK_FALSE,
            .minSampleShading = self.minSampleShading,
            .alphaToCoverageEnable = if (self.alphaToCoverageEnable) vulkan.VK_TRUE else vulkan.VK_FALSE,
            .alphaToOneEnable = if (self.alphaToOneEnable) vulkan.VK_TRUE else vulkan.VK_FALSE,
        };
    }
};

// --- Color blending.

pub const VkBlendFactor = enum(c_uint) {
    zero = 0,
    one = 1,
    src_color = 2,
    one_minus_src_color = 3,
    dst_color = 4,
    one_minus_dst_color = 5,
    src_alpha = 6,
    one_minus_src_alpha = 7,
    dst_alpha = 8,
    one_minus_dst_alpha = 9,
    constant_color = 10,
    one_minus_constant_color = 11,
    constant_alpha = 12,
    one_minus_constant_alpha = 13,
    src_alpha_saturate = 14,
    src1_color = 15,
    one_minus_src1_color = 16,
    src1_alpha = 17,
    one_minus_src1_alpha = 18,
    max_enum = 2147483647,
};

pub const VkBlendOp = enum(c_uint) {
    add = 0,
    subtract = 1,
    reverse_subtract = 2,
    min = 3,
    max = 4,
    zero_ext = 1000148000,
    src_ext = 1000148001,
    dst_ext = 1000148002,
    src_over_ext = 1000148003,
    dst_over_ext = 1000148004,
    src_in_ext = 1000148005,
    dst_in_ext = 1000148006,
    src_out_ext = 1000148007,
    dst_out_ext = 1000148008,
    src_atop_ext = 1000148009,
    dst_atop_ext = 1000148010,
    xor_ext = 1000148011,
    multiply_ext = 1000148012,
    screen_ext = 1000148013,
    overlay_ext = 1000148014,
    darken_ext = 1000148015,
    lighten_ext = 1000148016,
    colordodge_ext = 1000148017,
    colorburn_ext = 1000148018,
    hardlight_ext = 1000148019,
    softlight_ext = 1000148020,
    difference_ext = 1000148021,
    exclusion_ext = 1000148022,
    invert_ext = 1000148023,
    invert_rgb_ext = 1000148024,
    lineardodge_ext = 1000148025,
    linearburn_ext = 1000148026,
    vividlight_ext = 1000148027,
    linearlight_ext = 1000148028,
    pinlight_ext = 1000148029,
    hardmix_ext = 1000148030,
    hsl_hue_ext = 1000148031,
    hsl_saturation_ext = 1000148032,
    hsl_color_ext = 1000148033,
    hsl_luminosity_ext = 1000148034,
    plus_ext = 1000148035,
    plus_clamped_ext = 1000148036,
    plus_clamped_alpha_ext = 1000148037,
    plus_darker_ext = 1000148038,
    minus_ext = 1000148039,
    minus_clamped_ext = 1000148040,
    contrast_ext = 1000148041,
    invert_ovg_ext = 1000148042,
    red_ext = 1000148043,
    green_ext = 1000148044,
    blue_ext = 1000148045,
    max_enum = 2147483647,
};

pub const VkColorComponentFlags = packed struct(u32) {
    r: bool = false,
    g: bool = false,
    b: bool = false,
    a: bool = false,

    _: u28 = 0,

    pub const Bits = enum(c_uint) {
        r = 1,
        g = 2,
        b = 4,
        a = 8,
    };
};

pub const VkPipelineColorBlendAttachmentState = struct {
    blendEnable: bool,
    srcColorBlendFactor: VkBlendFactor,
    dstColorBlendFactor: VkBlendFactor,
    colorBlendOp: VkBlendOp,
    srcAlphaBlendFactor: VkBlendFactor,
    dstAlphaBlendFactor: VkBlendFactor,
    alphaBlendOp: VkBlendOp,
    colorWriteMask: VkColorComponentFlags,

    pub fn to_vulkan_ty(self: VkPipelineColorBlendAttachmentState) vulkan.VkPipelineColorBlendAttachmentState {
        return .{
            .blendEnable = if (self.blendEnable) vulkan.VK_TRUE else vulkan.VK_FALSE,
            .srcColorBlendFactor = @intFromEnum(self.srcColorBlendFactor),
            .dstColorBlendFactor = @intFromEnum(self.dstColorBlendFactor),
            .colorBlendOp = @intFromEnum(self.colorBlendOp),
            .srcAlphaBlendFactor = @intFromEnum(self.srcAlphaBlendFactor),
            .dstAlphaBlendFactor = @intFromEnum(self.dstAlphaBlendFactor),
            .alphaBlendOp = @intFromEnum(self.alphaBlendOp),
            .colorWriteMask = @bitCast(self.colorWriteMask),
        };
    }
};

pub const VkPipelineColorBlendStateCreateFlags = packed struct(u32) {
    rasterization_order_attachment_access_ext: bool = false,
    _: u31 = 0,

    pub const Bits = enum(c_uint) {
        rasterization_order_attachment_access_ext = 1,
    };
};

pub const VkLogicOp = enum(c_uint) {
    clear = 0,
    and_ = 1,
    and_reverse = 2,
    copy = 3,
    and_inverted = 4,
    no_op = 5,
    xor_ = 6,
    or_ = 7,
    nor = 8,
    equivalent = 9,
    invert = 10,
    or_reverse = 11,
    copy_inverted = 12,
    or_inverted = 13,
    nand = 14,
    set = 15,
    max_enum = 2147483647,
};

pub const VkPipelineColorBlendStateCreateInfo = struct {
    pNext: ?*const anyopaque = null,
    flags: VkPipelineColorBlendStateCreateFlags = .{},
    logicOpEnable: bool,
    logicOp: VkLogicOp,
    attachments: []const VkPipelineColorBlendAttachmentState,
    blendConstants: [4]f32,

    pub fn to_vulkan_ty(self: VkPipelineColorBlendStateCreateInfo, allocator: std.mem.Allocator) vulkan.VkPipelineColorBlendStateCreateInfo {
        var attachments: []vulkan.VkPipelineColorBlendAttachmentState = allocator.alloc(
            vulkan.VkPipelineColorBlendAttachmentState,
            self.attachments.len,
        ) catch {
            @panic("l0vk out of memory");
        };
        var i: usize = 0;
        while (i < self.attachments.len) : (i += 1) {
            attachments[i] = self.attachments[i].to_vulkan_ty();
        }

        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .pNext = self.pNext,
            .flags = @bitCast(self.flags),
            .logicOpEnable = if (self.logicOpEnable) vulkan.VK_TRUE else vulkan.VK_FALSE,
            .logicOp = @intFromEnum(self.logicOp),
            .attachmentCount = @intCast(attachments.len),
            .pAttachments = attachments.ptr,
            .blendConstants = self.blendConstants,
        };
    }
};

// --- Pipeline

pub const VkPipelineCreateFlags = packed struct(u32) {
    disable_optimization: bool = false,
    allow_derivatives: bool = false,
    derivative: bool = false,
    view_index_from_device_index: bool = false,

    dispatch_base: bool = false,
    fail_on_pipeline_compile_required: bool = false,
    early_return_on_failure: bool = false,
    rendering_fragment_shading_rate_attachment_khr: bool = false,

    rendering_fragment_density_map_attachment_ext: bool = false,
    ray_tracing_no_null_any_hit_shaders_khr: bool = false,
    ray_tracing_no_null_closest_hit_shaders_khr: bool = false,
    ray_tracing_no_null_miss_shaders_khr: bool = false,

    ray_tracing_no_null_intersection_shaders_khr: bool = false,
    ray_tracing_skip_triangles_khr: bool = false,
    ray_tracing_skip_aabbs_khr: bool = false,
    ray_tracing_shader_group_handle_capture_replay_khr: bool = false,

    defer_compile_nv: bool = false,
    capture_statistics_khr: bool = false,
    capture_internal_representations_khr: bool = false,
    indirect_bindable_nv: bool = false,

    library_khr: bool = false,
    descriptor_buffer_ext: bool = false,
    retain_link_time_optimization_info_ext: bool = false,
    link_time_optimization_ext: bool = false,

    ray_tracing_allow_motion_nv: bool = false,
    color_attachment_feedback_loop_ext: bool = false,
    depth_stencil_attachment_feedback_loop_ext: bool = false,
    ray_tracing_opacity_micromap_ext: bool = false,

    no_protected_access_ext: bool = false,
    protected_access_only_ext: bool = false,
    _: u2 = 0,

    pub const Bits = enum(u32) {
        disable_optimization = 0x00000001,
        allow_derivatives = 0x00000002,
        derivative = 0x00000004,
        view_index_from_device_index = 0x00000008,

        dispatch_base = 0x00000010,
        fail_on_pipeline_compile_required = 0x00000100,
        early_return_on_failure = 0x00000200,
        rendering_fragment_shading_rate_attachment_khr = 0x00200000,

        rendering_fragment_density_map_attachment_ext = 0x00400000,
        ray_tracing_no_null_any_hit_shaders_khr = 0x00004000,
        ray_tracing_no_null_closest_hit_shaders_khr = 0x00008000,
        ray_tracing_no_null_miss_shaders_khr = 0x00010000,

        ray_tracing_no_null_intersection_shaders_khr = 0x00020000,
        ray_tracing_skip_triangles_khr = 0x00001000,
        ray_tracing_skip_aabbs_khr = 0x00002000,
        ray_tracing_shader_group_handle_capture_replay_khr = 0x00080000,

        defer_compile_nv = 0x00000020,
        capture_statistics_khr = 0x00000040,
        capture_internal_representations_khr = 0x00000080,
        indirect_bindable_nv = 0x00040000,

        library_khr = 0x00000800,
        descriptor_buffer_ext = 0x20000000,
        retain_link_time_optimization_info_ext = 0x00800000,
        link_time_optimization_ext = 0x00000400,

        ray_tracing_allow_motion_nv = 0x00100000,
        color_attachment_feedback_loop_ext = 0x02000000,
        depth_stencil_attachment_feedback_loop_ext = 0x04000000,
        ray_tracing_opacity_micromap_ext = 0x01000000,

        no_protected_access_ext = 0x08000000,
        protected_access_only_ext = 0x40000000,
    };
};

pub const VkPipelineTessellationStateCreateInfo = struct {
    pNext: ?*const anyopaque = null,
    patchControlPoints: u32,

    pub fn to_vulkan_ty(self: VkPipelineTessellationStateCreateInfo) vulkan.VkPipelineTessellationStateCreateInfo {
        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_TESSELLATION_STATE_CREATE_INFO,
            .pNext = self.pNext,
            .patchControlPoints = self.patchControlPoints,
            .flags = 0,
        };
    }
};

pub const VkPipelineDepthStencilStateCreateFlags = packed struct(u32) {
    rasterization_order_attachment_depth_access_ext: bool = false,
    rasterization_order_attachment_stencil_access_ext: bool = false,
    _: u30 = 0,

    pub const Bits = enum(u32) {
        rasterization_order_attachment_depth_access_ext = 0x00000001,
        rasterization_order_attachment_stencil_access_ext = 0x00000002,
    };
};

pub const VkCompareOp = enum(c_uint) {
    never = 0,
    less = 1,
    equal = 2,
    less_or_equal = 3,
    greater = 4,
    not_equal = 5,
    greater_or_equal = 6,
    always = 7,
};

pub const VkStencilOp = enum(c_uint) {
    keep = 0,
    zero = 1,
    replace = 2,
    increment_and_clamp = 3,
    decrement_and_clamp = 4,
    invert = 5,
    increment_and_wrap = 6,
    decrement_and_wrap = 7,
    max_enum = 2147483647,
};

pub const VkStencilOpState = struct {
    failOp: VkStencilOp,
    passOp: VkStencilOp,
    depthFailOp: VkStencilOp,
    compareOp: VkCompareOp,
    compareMask: u32,
    writeMask: u32,
    reference: u32,

    pub fn to_vulkan_ty(self: VkStencilOpState) vulkan.VkStencilOpState {
        return .{
            .failOp = @intFromEnum(self.failOp),
            .passOp = @intFromEnum(self.passOp),
            .depthFailOp = @intFromEnum(self.depthFailOp),
            .compareOp = @intFromEnum(self.compareOp),
            .compareMask = self.compareMask,
            .writeMask = self.writeMask,
            .reference = self.reference,
        };
    }
};

pub const VkPipelineDepthStencilStateCreateInfo = struct {
    pNext: ?*const anyopaque = null,
    flags: VkPipelineDepthStencilStateCreateFlags = @import("std").mem.zeroes(VkPipelineDepthStencilStateCreateFlags),
    depthTestEnable: bool,
    depthWriteEnable: bool,
    depthCompareOp: VkCompareOp = @import("std").mem.zeroes(VkCompareOp),
    depthBoundsTestEnable: bool,
    stencilTestEnable: bool,
    front: VkStencilOpState,
    back: VkStencilOpState,
    minDepthBounds: f32,
    maxDepthBounds: f32,

    pub fn to_vulkan_ty(self: VkPipelineDepthStencilStateCreateInfo) vulkan.VkPipelineDepthStencilStateCreateInfo {
        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            .pNext = self.pNext,
            .flags = @bitCast(self.flags),
            .depthTestEnable = if (self.depthTestEnable) vulkan.VK_TRUE else vulkan.VK_FALSE,
            .depthWriteEnable = if (self.depthWriteEnable) vulkan.VK_TRUE else vulkan.VK_FALSE,
            .depthCompareOp = @intFromEnum(self.depthCompareOp),
            .depthBoundsTestEnable = if (self.depthBoundsTestEnable) vulkan.VK_TRUE else vulkan.VK_FALSE,
            .stencilTestEnable = if (self.stencilTestEnable) vulkan.VK_TRUE else vulkan.VK_FALSE,
            .front = self.front.to_vulkan_ty(),
            .back = self.back.to_vulkan_ty(),
            .minDepthBounds = self.minDepthBounds,
            .maxDepthBounds = self.maxDepthBounds,
        };
    }
};

pub const VkGraphicsPipelineCreateInfo = struct {
    pNext: ?*const anyopaque = null,
    flags: VkPipelineCreateFlags = .{},
    stages: []const VkPipelineShaderStageCreateInfo,

    pVertexInputState: ?*const VkPipelineVertexInputStateCreateInfo,
    pInputAssemblyState: ?*const VkPipelineInputAssemblyStateCreateInfo,
    pTessellationState: ?*const VkPipelineTessellationStateCreateInfo,
    pViewportState: ?*const VkPipelineViewportStateCreateInfo,
    pRasterizationState: ?*const VkPipelineRasterizationStateCreateInfo,
    pMultisampleState: ?*const VkPipelineMultisampleStateCreateInfo,
    pDepthStencilState: ?*const VkPipelineDepthStencilStateCreateInfo,
    pColorBlendState: ?*const VkPipelineColorBlendStateCreateInfo,
    pDynamicState: ?*const VkPipelineDynamicStateCreateInfo,

    layout: VkPipelineLayout,
    renderPass: l0vk.VkRenderPass,
    subpass: u32,
    basePipelineHandle: VkPipeline,
    basePipelineIndex: i32,

    pub fn to_vulkan_ty(self: VkGraphicsPipelineCreateInfo, allocator: std.mem.Allocator) vulkan.VkGraphicsPipelineCreateInfo {
        var shader_stages = allocator.alloc(vulkan.VkPipelineShaderStageCreateInfo, self.stages.len) catch {
            @panic("l0vk ran out of memory");
        };
        var i: usize = 0;
        while (i < self.stages.len) : (i += 1) {
            shader_stages[i] = self.stages[i].to_vulkan_ty(allocator);
        }

        // --

        var p_vertex_input_state: ?*vulkan.VkPipelineVertexInputStateCreateInfo = null;
        if (self.pVertexInputState != null) {
            p_vertex_input_state = allocator.create(
                vulkan.VkPipelineVertexInputStateCreateInfo,
            ) catch {
                @panic("l0vk ran out of memory");
            };
            p_vertex_input_state.?.* = self.pVertexInputState.?.to_vulkan_ty(allocator);
        }

        var p_input_assembly: ?*vulkan.VkPipelineInputAssemblyStateCreateInfo = null;
        if (self.pInputAssemblyState != null) {
            p_input_assembly = allocator.create(
                vulkan.VkPipelineInputAssemblyStateCreateInfo,
            ) catch {
                @panic("l0vk ran out of memory");
            };
            p_input_assembly.?.* = self.pInputAssemblyState.?.to_vulkan_ty();
        }

        var p_tesselation_state: ?*vulkan.VkPipelineTessellationStateCreateInfo = null;
        if (self.pTessellationState != null) {
            p_tesselation_state = allocator.create(
                vulkan.VkPipelineTessellationStateCreateInfo,
            ) catch {
                @panic("l0vk ran out of memory");
            };
            p_tesselation_state.?.* = self.pTessellationState.?.to_vulkan_ty();
        }

        var p_viewport_state: ?*vulkan.VkPipelineViewportStateCreateInfo = null;
        if (self.pViewportState != null) {
            p_viewport_state = allocator.create(
                vulkan.VkPipelineViewportStateCreateInfo,
            ) catch {
                @panic("l0vk ran out of memory");
            };
            p_viewport_state.?.* = self.pViewportState.?.to_vulkan_ty();
        }

        var p_rasterization_state: ?*vulkan.VkPipelineRasterizationStateCreateInfo = null;
        if (self.pRasterizationState != null) {
            p_rasterization_state = allocator.create(
                vulkan.VkPipelineRasterizationStateCreateInfo,
            ) catch {
                @panic("l0vk ran out of memory");
            };
            p_rasterization_state.?.* = self.pRasterizationState.?.to_vulkan_ty();
        }

        var p_multisample_state: ?*vulkan.VkPipelineMultisampleStateCreateInfo = null;
        if (self.pMultisampleState != null) {
            p_multisample_state = allocator.create(
                vulkan.VkPipelineMultisampleStateCreateInfo,
            ) catch {
                @panic("l0vk ran out of memory");
            };
            p_multisample_state.?.* = self.pMultisampleState.?.to_vulkan_ty();
        }

        var p_depth_stencil_state: ?*vulkan.VkPipelineDepthStencilStateCreateInfo = null;
        if (self.pDepthStencilState != null) {
            p_depth_stencil_state = allocator.create(
                vulkan.VkPipelineDepthStencilStateCreateInfo,
            ) catch {
                @panic("l0vk ran out of memory");
            };
            p_depth_stencil_state.?.* = self.pDepthStencilState.?.to_vulkan_ty();
        }

        var p_color_blend_state: ?*vulkan.VkPipelineColorBlendStateCreateInfo = null;
        if (self.pColorBlendState != null) {
            p_color_blend_state = allocator.create(
                vulkan.VkPipelineColorBlendStateCreateInfo,
            ) catch {
                @panic("l0vk ran out of memory");
            };
            p_color_blend_state.?.* = self.pColorBlendState.?.to_vulkan_ty(allocator);
        }

        var p_dynamic_state: ?*vulkan.VkPipelineDynamicStateCreateInfo = null;
        if (self.pDynamicState != null) {
            p_dynamic_state = allocator.create(
                vulkan.VkPipelineDynamicStateCreateInfo,
            ) catch {
                @panic("l0vk ran out of memory");
            };
            p_dynamic_state.?.* = self.pDynamicState.?.to_vulkan_ty(allocator);
        }

        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .pNext = self.pNext,
            .flags = @bitCast(self.flags),
            .stageCount = @intCast(shader_stages.len),
            .pStages = shader_stages.ptr,

            .pVertexInputState = p_vertex_input_state,
            .pInputAssemblyState = p_input_assembly,
            .pTessellationState = p_tesselation_state,
            .pViewportState = p_viewport_state,
            .pRasterizationState = p_rasterization_state,
            .pMultisampleState = p_multisample_state,
            .pDepthStencilState = p_depth_stencil_state,
            .pColorBlendState = p_color_blend_state,
            .pDynamicState = p_dynamic_state,

            .layout = self.layout,
            .renderPass = self.renderPass,
            .subpass = self.subpass,
            .basePipelineHandle = self.basePipelineHandle,
            .basePipelineIndex = self.basePipelineIndex,
        };
    }
};

pub const VkPipelineCache = vulkan.VkPipelineCache;

pub const vkCreateGraphicsPipelinesError = error{
    VK_PIPELINE_COMPILE_REQUIRED_EXT,
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
    VK_ERROR_INVALID_SHADER_NV,

    OutOfMemory,
};

pub fn vkCreateGraphicsPipelines(
    allocator: std.mem.Allocator,
    device: l0vk.VkDevice,
    pipelineCache: VkPipelineCache,
    createInfos: []const VkGraphicsPipelineCreateInfo,
    pAllocator: [*c]const l0vk.VkAllocationCallbacks,
) vkCreateGraphicsPipelinesError![]VkPipeline {
    var buffer: [3000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    var fba_allocator = fba.allocator();

    // ---

    var pipelines = try allocator.alloc(VkPipeline, createInfos.len);

    var vk_createInfos = try fba_allocator.alloc(vulkan.VkGraphicsPipelineCreateInfo, createInfos.len);
    var i: usize = 0;
    while (i < createInfos.len) : (i += 1) {
        vk_createInfos[i] = createInfos[i].to_vulkan_ty(fba_allocator);
    }

    var result = vulkan.vkCreateGraphicsPipelines(
        device,
        pipelineCache,
        @intCast(vk_createInfos.len),
        vk_createInfos.ptr,
        pAllocator,
        pipelines.ptr,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_PIPELINE_COMPILE_REQUIRED_EXT => return vkCreateGraphicsPipelinesError.VK_PIPELINE_COMPILE_REQUIRED_EXT,
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkCreateGraphicsPipelinesError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkCreateGraphicsPipelinesError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_INVALID_SHADER_NV => return vkCreateGraphicsPipelinesError.VK_ERROR_INVALID_SHADER_NV,
            else => unreachable,
        }
    }

    return pipelines;
}
