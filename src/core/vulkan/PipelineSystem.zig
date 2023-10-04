const std = @import("std");
const vulkan = @import("../../c/vulkan.zig");
const VulkanError = @import("./VulkanSystem.zig").VulkanError;
const Core = @import("../Core.zig");
const Vertex = @import("../../vertex.zig").Vertex;

const PipelineSystem = @This();

pipeline_layout_cache: std.StringHashMap(vulkan.VkPipelineLayout),
pipeline_cache: std.StringHashMap(vulkan.VkPipeline),

pub const PipelineInitInfo = struct {
    kind: Kind,

    pub const Kind = enum {
        default,
    };

    pub fn init_swapchain() PipelineInitInfo {
        return .{
            .kind = .default,
        };
    }
};

pub fn init(allocator_: std.mem.Allocator) VulkanError!PipelineSystem {
    const pipeline_layout_cache = std.StringHashMap(vulkan.VkPipelineLayout).init(allocator_);
    const pipeline_cache = std.StringHashMap(vulkan.VkPipeline).init(allocator_);

    return .{
        .pipeline_layout_cache = pipeline_layout_cache,
        .pipeline_cache = pipeline_cache,
    };
}

pub fn deinit(self: *PipelineSystem, device: vulkan.VkDevice) void {
    var layout_iterator = self.pipeline_layout_cache.iterator();
    while (layout_iterator.next()) |entry| {
        vulkan.vkDestroyPipelineLayout(device, entry.value_ptr.*, null);
    }
    var pipeline_iterator = self.pipeline_cache.iterator();
    while (pipeline_iterator.next()) |entry| {
        vulkan.vkDestroyPipeline(device, entry.value_ptr.*, null);
    }

    self.pipeline_layout_cache.deinit();
    self.pipeline_cache.deinit();
}

pub const PipelineAndLayout = struct {
    pipeline: vulkan.VkPipeline,
    layout: vulkan.VkPipelineLayout,
};

pub fn build_pipeline(
    self: *PipelineSystem,
    core: *Core,
    info: PipelineInitInfo,
    render_pass: vulkan.VkRenderPass,
) VulkanError!PipelineAndLayout {
    const layout = try self.get_or_build_pipeline_layout(core, info, render_pass);

    return .{
        .layout = layout,
    };
}

pub fn get_or_build_pipeline_layout(
    self: *PipelineSystem,
    core: *Core,
    info: PipelineInitInfo,
    render_pass: vulkan.VkRenderPass,
) VulkanError!vulkan.VkPipelineLayout {
    _ = render_pass;

    switch (info.kind) {
        .default => {
            const cache_value = self.pipeline_layout_cache.get("default");
            if (cache_value != null) {
                return cache_value.?;
            }

            const layout = try build_default_pipeline_layout(core);
            try self.pipeline_layout_cache.put("default", layout);
            return layout;
        },
    }
}

pub fn get_or_build_pipeline(
    self: *PipelineSystem,
    core: *Core,
    info: PipelineInitInfo,
    render_pass: vulkan.VkRenderPass,
) VulkanError!vulkan.VkPipeline {
    switch (info.kind) {
        .default => {
            const cache_value = self.pipeline_cache.get("default");
            if (cache_value != null) {
                return cache_value.?;
            }

            const layout = try self.get_or_build_pipeline_layout(core, info, render_pass);
            const pipeline = try build_default_pipeline(core, layout, render_pass);
            try self.pipeline_cache.put("default", pipeline);
            return pipeline;
        },
    }
}

fn build_default_pipeline_layout(core: *Core) VulkanError!vulkan.VkPipelineLayout {
    const pipeline_layout_info = vulkan.VkPipelineLayoutCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,

        // Default:
        .setLayoutCount = 0,
        .pSetLayouts = null,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
        .pNext = null,
        .flags = 0,
    };

    var pipeline_layout: vulkan.VkPipelineLayout = undefined;
    var result = vulkan.vkCreatePipelineLayout(core.vulkan_system.logical_device, &pipeline_layout_info, null, &pipeline_layout);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            else => unreachable,
        }
    }

    return pipeline_layout;
}

fn build_default_pipeline(
    core: *Core,
    layout: vulkan.VkPipelineLayout,
    render_pass: vulkan.VkRenderPass,
) VulkanError!vulkan.VkPipeline {
    const vert_shader_code = try read_file("shaders/compiled_output/triangle.vert.spv", core.allocator);
    defer core.allocator.free(vert_shader_code);
    const frag_shader_code = try read_file("shaders/compiled_output/triangle.frag.spv", core.allocator);
    defer core.allocator.free(frag_shader_code);

    const vert_shader_module = try create_shader_module(core.vulkan_system.logical_device, vert_shader_code);
    const frag_shader_module = try create_shader_module(core.vulkan_system.logical_device, frag_shader_code);

    // ---

    var vert_shader_stage_pipeline_create_info = vulkan.VkPipelineShaderStageCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vulkan.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vert_shader_module,
        .pName = "main",

        .pSpecializationInfo = null,
        .pNext = null,
        .flags = 0,
    };

    var frag_shader_stage_pipeline_create_info = vulkan.VkPipelineShaderStageCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vulkan.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = frag_shader_module,
        .pName = "main",

        .pSpecializationInfo = null,
        .pNext = null,
        .flags = 0,
    };

    const shader_stages = [_]vulkan.VkPipelineShaderStageCreateInfo{
        vert_shader_stage_pipeline_create_info,
        frag_shader_stage_pipeline_create_info,
    };

    // --- Input assembly.

    const vertex_input_info = vulkan.VkPipelineVertexInputStateCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 0,
        .pVertexBindingDescriptions = null,
        .vertexAttributeDescriptionCount = 0,
        .pVertexAttributeDescriptions = null,
        .pNext = null,
        .flags = 0,
    };

    const input_assembly = vulkan.VkPipelineInputAssemblyStateCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = vulkan.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = vulkan.VK_FALSE,
        .pNext = null,
        .flags = 0,
    };

    // --- Viewport and scissor.

    const dynamic_states = [_]vulkan.VkDynamicState{
        vulkan.VK_DYNAMIC_STATE_VIEWPORT,
        vulkan.VK_DYNAMIC_STATE_SCISSOR,
    };
    const dynamic_state = vulkan.VkPipelineDynamicStateCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = dynamic_states.len,
        .pDynamicStates = dynamic_states[0..].ptr,
        .pNext = null,
        .flags = 0,
    };

    const viewport_state = vulkan.VkPipelineViewportStateCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .scissorCount = 1,
        .pViewports = null,
        .pScissors = null,
        .pNext = null,
        .flags = 0,
    };

    // --- Rasterizer.

    const rasterizer = vulkan.VkPipelineRasterizationStateCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depthClampEnable = vulkan.VK_FALSE,
        .rasterizerDiscardEnable = vulkan.VK_FALSE,
        .polygonMode = vulkan.VK_POLYGON_MODE_FILL,
        .lineWidth = 1.0,
        .cullMode = vulkan.VK_CULL_MODE_BACK_BIT,
        .frontFace = vulkan.VK_FRONT_FACE_CLOCKWISE, // CW / CCW
        .depthBiasEnable = vulkan.VK_FALSE,
        .pNext = null,
        .flags = 0,
        .depthBiasConstantFactor = 0.0,
        .depthBiasClamp = 0.0,
        .depthBiasSlopeFactor = 0.0,
    };

    // --- Multisampling.

    const multisampling = vulkan.VkPipelineMultisampleStateCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .sampleShadingEnable = vulkan.VK_FALSE,
        .rasterizationSamples = vulkan.VK_SAMPLE_COUNT_1_BIT,
        // Default:
        .minSampleShading = 1.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = vulkan.VK_FALSE,
        .alphaToOneEnable = vulkan.VK_FALSE,
        .pNext = null,
        .flags = 0,
    };

    // --- Color blending.

    const color_blend_attachment = vulkan.VkPipelineColorBlendAttachmentState{
        .colorWriteMask = vulkan.VK_COLOR_COMPONENT_R_BIT | vulkan.VK_COLOR_COMPONENT_G_BIT | vulkan.VK_COLOR_COMPONENT_B_BIT | vulkan.VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = vulkan.VK_FALSE,
        // Default:
        .srcColorBlendFactor = vulkan.VK_BLEND_FACTOR_ONE,
        .dstColorBlendFactor = vulkan.VK_BLEND_FACTOR_ZERO,
        .colorBlendOp = vulkan.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = vulkan.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = vulkan.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = vulkan.VK_BLEND_OP_ADD,
    };

    const color_blending = vulkan.VkPipelineColorBlendStateCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .logicOpEnable = vulkan.VK_FALSE,
        .logicOp = vulkan.VK_LOGIC_OP_COPY, // Ignored.
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
        // Default:
        .blendConstants = [_]f32{
            0.0,
            0.0,
            0.0,
            0.0,
        },
        .pNext = null,
        .flags = 0,
    };

    // -- Pipeline.

    const pipeline_info = vulkan.VkGraphicsPipelineCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = shader_stages.len,
        .pStages = shader_stages[0..].ptr,
        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &input_assembly,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pColorBlendState = &color_blending,
        .pDynamicState = &dynamic_state,
        .layout = layout,
        .renderPass = render_pass,
        .subpass = 0,
        .pDepthStencilState = null,

        .basePipelineHandle = @ptrCast(vulkan.VK_NULL_HANDLE),
        .basePipelineIndex = -1,
        .pNext = null,
        .flags = 0,
        .pTessellationState = null,
    };

    var pipeline: vulkan.VkPipeline = undefined;
    var result = vulkan.vkCreateGraphicsPipelines(core.vulkan_system.logical_device, @ptrCast(vulkan.VK_NULL_HANDLE), 1, &pipeline_info, null, &pipeline);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            vulkan.VK_ERROR_INVALID_SHADER_NV => return VulkanError.vk_error_invalid_shader_nv,
            else => unreachable,
        }
    }

    // ---

    vulkan.vkDestroyShaderModule(core.vulkan_system.logical_device, vert_shader_module, null);
    vulkan.vkDestroyShaderModule(core.vulkan_system.logical_device, frag_shader_module, null);

    return pipeline;
}

fn read_file(filename: []const u8, allocator: std.mem.Allocator) VulkanError![]const u8 {
    const file = std.fs.cwd().openFile(filename, .{}) catch {
        return VulkanError.file_not_found;
    };
    defer file.close();

    const buf = file.readToEndAlloc(allocator, std.math.maxInt(usize)) catch {
        return VulkanError.file_loading_failed;
    };
    return buf;
}

fn create_shader_module(device: vulkan.VkDevice, code: []const u8) VulkanError!vulkan.VkShaderModule {
    const shader_module_create_info = vulkan.VkShaderModuleCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = @intCast(code.len),
        .pCode = @ptrCast(@alignCast(code.ptr)),

        .pNext = null,
        .flags = 0,
    };

    var shader_module: vulkan.VkShaderModule = undefined;
    const result = vulkan.vkCreateShaderModule(device, &shader_module_create_info, null, &shader_module);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            vulkan.VK_ERROR_INVALID_SHADER_NV => return VulkanError.vk_error_invalid_shader_nv,
            else => unreachable,
        }
    }

    return shader_module;
}
