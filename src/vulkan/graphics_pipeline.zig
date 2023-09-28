const std = @import("std");
const vulkan = @import("../c.zig").vulkan;

const VulkanError = @import("./vulkan.zig").VulkanError;
const Swapchain = @import("./swapchain.zig");
const Vertex = @import("../vertex.zig");

const GraphicsPipeline = @This();

device: vulkan.VkDevice,

pipeline_layout: vulkan.VkPipelineLayout,
pipeline: vulkan.VkPipeline,

pub fn init(
    allocator_: std.mem.Allocator,
    device: vulkan.VkDevice,
    swapchain: *const Swapchain,
    render_pass: vulkan.VkRenderPass,
    descriptor_set_layout: vulkan.VkDescriptorSetLayout,
) VulkanError!GraphicsPipeline {
    _ = swapchain;
    const vert_shader_code = try read_file("shaders/compiled_output/shader.vert.spv", allocator_);
    defer allocator_.free(vert_shader_code);
    const frag_shader_code = try read_file("shaders/compiled_output/shader.frag.spv", allocator_);
    defer allocator_.free(frag_shader_code);

    const vert_shader_module = try create_shader_module(device, vert_shader_code);
    const frag_shader_module = try create_shader_module(device, frag_shader_code);

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

    const binding_descrpition = Vertex.Vertex.get_binding_description();
    const attribute_descrpitions = Vertex.Vertex.get_attribute_descriptions();

    const vertex_input_info = vulkan.VkPipelineVertexInputStateCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &binding_descrpition,
        .vertexAttributeDescriptionCount = @intCast(attribute_descrpitions.len),
        .pVertexAttributeDescriptions = attribute_descrpitions[0..].ptr,
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
        .frontFace = vulkan.VK_FRONT_FACE_COUNTER_CLOCKWISE,
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

    // -- Pipeline layout.

    const pipeline_layout_info = vulkan.VkPipelineLayoutCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &descriptor_set_layout,
        // Default:
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
        .pNext = null,
        .flags = 0,
    };

    var pipeline_layout: vulkan.VkPipelineLayout = undefined;
    var result = vulkan.vkCreatePipelineLayout(device, &pipeline_layout_info, null, &pipeline_layout);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            else => unreachable,
        }
    }

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
        .layout = pipeline_layout,
        .renderPass = render_pass,
        .subpass = 0,

        .basePipelineHandle = @ptrCast(vulkan.VK_NULL_HANDLE),
        .basePipelineIndex = -1,
        .pNext = null,
        .flags = 0,
        .pTessellationState = null,
        .pDepthStencilState = null,
    };

    var pipeline: vulkan.VkPipeline = undefined;
    result = vulkan.vkCreateGraphicsPipelines(device, @ptrCast(vulkan.VK_NULL_HANDLE), 1, &pipeline_info, null, &pipeline);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            vulkan.VK_ERROR_INVALID_SHADER_NV => return VulkanError.vk_error_invalid_shader_nv,
            else => unreachable,
        }
    }

    // ---

    vulkan.vkDestroyShaderModule(device, vert_shader_module, null);
    vulkan.vkDestroyShaderModule(device, frag_shader_module, null);

    return .{
        .device = device,
        .pipeline_layout = pipeline_layout,
        .pipeline = pipeline,
    };
}

pub fn deinit(self: GraphicsPipeline) void {
    vulkan.vkDestroyPipeline(self.device, self.pipeline, null);
    vulkan.vkDestroyPipelineLayout(self.device, self.pipeline_layout, null);
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
