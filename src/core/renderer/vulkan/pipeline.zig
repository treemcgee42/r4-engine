const std = @import("std");
const VulkanSystem = @import("./VulkanSystem.zig");
const VulkanError = VulkanSystem.VulkanError;
const l0vk = @import("../layer0/vulkan/vulkan.zig");
const dutil = @import("debug_utils");

pub const PipelineSystem = struct {
    pipelines: std.StringHashMap(l0vk.VkPipeline),
    pipeline_layouts: std.StringHashMap(l0vk.VkPipelineLayout),

    pub fn init(allocator: std.mem.Allocator) PipelineSystem {
        const pipelines = std.StringHashMap(l0vk.VkPipeline).init(allocator);
        const pipeline_layouts = std.StringHashMap(l0vk.VkPipelineLayout).init(allocator);

        return .{
            .pipelines = pipelines,
            .pipeline_layouts = pipeline_layouts,
        };
    }

    pub fn deinit(self: *PipelineSystem, system: *VulkanSystem) void {
        var pipeline_layouts_iterator = self.pipeline_layouts.iterator();
        while (true) {
            const pipeline_layout = pipeline_layouts_iterator.next();
            if (pipeline_layout == null) {
                break;
            }

            l0vk.vkDestroyPipelineLayout(system.logical_device, pipeline_layout.?.value_ptr.*, null);
        }
        self.pipeline_layouts.deinit();

        var pipelines_iterator = self.pipelines.iterator();
        while (true) {
            const pipeline = pipelines_iterator.next();
            if (pipeline == null) {
                break;
            }

            l0vk.vkDestroyPipeline(system.logical_device, pipeline.?.value_ptr.*, null);
        }
        self.pipelines.deinit();
    }

    pub fn create(
        self: *PipelineSystem,
        system: *VulkanSystem,
        name: []const u8,
        info: PipelineCreateInfo,
    ) !PipelineAndLayout {
        const pipeline_and_layout = try build_pipeline(system, info);
        errdefer {
            l0vk.vkDestroyPipelineLayout(system.logical_device, pipeline_and_layout.pipeline_layout, null);
            l0vk.vkDestroyPipeline(system.logical_device, pipeline_and_layout.pipeline, null);
        }

        if (self.pipelines.contains(name)) {
            dutil.log(
                "pipeline system",
                .warn,
                \\attempting to create pipeline with name '{s}', 
                \\but a pipeline with that name already exists in the system... 
                \\will override it, but won't destroy it
            ,
                .{name},
            );
        }

        try self.pipelines.put(name, pipeline_and_layout.pipeline);
        errdefer _ = self.pipelines.remove(name);
        try self.pipeline_layouts.put(name, pipeline_and_layout.pipeline_layout);

        return pipeline_and_layout;
    }
};

const PipelineAndLayout = struct {
    pipeline: l0vk.VkPipeline,
    pipeline_layout: l0vk.VkPipelineLayout,
};

pub const PipelineCreateInfo = struct {
    vertex_shader_filename: []const u8,
    fragment_shader_filename: []const u8,
    renderpass_name: []const u8,

    depth_test_enabled: bool = false,
    vertex_binding_descriptions: []l0vk.VkVertexInputBindingDescription = &.{},
    attribute_descriptions: []const l0vk.VkVertexInputAttributeDescription = &.{},
    push_constant_ranges: []l0vk.VkPushConstantRange = &.{},
};

pub fn build_pipeline(system: *VulkanSystem, create_info: PipelineCreateInfo) !PipelineAndLayout {
    const allocator = system.allocator;

    var pipeline_layout_info = l0vk.VkPipelineLayoutCreateInfo{};
    pipeline_layout_info.pushConstantRanges = create_info.push_constant_ranges;
    const pipeline_layout = try l0vk.vkCreatePipelineLayout(
        system.logical_device,
        &pipeline_layout_info,
        null,
    );

    // ---

    const vert_shader_code = try read_file(create_info.vertex_shader_filename, allocator);
    defer allocator.free(vert_shader_code);
    const frag_shader_code = try read_file(create_info.fragment_shader_filename, allocator);
    defer allocator.free(frag_shader_code);

    const vert_shader_module = try create_shader_module(system.logical_device, vert_shader_code);
    const frag_shader_module = try create_shader_module(system.logical_device, frag_shader_code);

    // ---

    const vert_shader_stage_pipeline_create_info = l0vk.VkPipelineShaderStageCreateInfo{
        .stage = l0vk.VkShaderStageFlags.Bits.vertex,
        .module = vert_shader_module,
        .pName = "main",
    };

    const frag_shader_stage_pipeline_create_info = l0vk.VkPipelineShaderStageCreateInfo{
        .stage = l0vk.VkShaderStageFlags.Bits.fragment,
        .module = frag_shader_module,
        .pName = "main",
    };

    const shader_stages = [_]l0vk.VkPipelineShaderStageCreateInfo{
        vert_shader_stage_pipeline_create_info,
        frag_shader_stage_pipeline_create_info,
    };

    // --- Input assembly.

    const vertex_input_info = l0vk.VkPipelineVertexInputStateCreateInfo{
        .vertex_binding_descriptions = create_info.vertex_binding_descriptions,
        .vertex_attribute_descriptions = create_info.attribute_descriptions,
    };

    const topology = l0vk.VkPrimitiveTopology.triangle_list;

    const input_assembly = l0vk.VkPipelineInputAssemblyStateCreateInfo{
        .topology = topology,
        .primitiveRestartEnable = false,
    };

    // --- Viewport and scissor.

    const dynamic_states = [_]l0vk.VkDynamicState{
        .viewport,
        .scissor,
    };
    const dynamic_state = l0vk.VkPipelineDynamicStateCreateInfo{
        .dynamic_states = &dynamic_states,
    };

    const viewport_state = l0vk.VkPipelineViewportStateCreateInfo{
        .viewportCount = 1,
        .viewports = &[_]l0vk.VkViewport{},
        .scissorCount = 1,
        .scissors = &[_]l0vk.VkRect2D{},
    };

    // --- Rasterizer.

    const frontFace = l0vk.VkFrontFace.counter_clockwise;

    const rasterizer = l0vk.VkPipelineRasterizationStateCreateInfo{
        .depthClampEnable = false,
        .rasterizerDiscardEnable = false,
        .polygonMode = .fill,
        .lineWidth = 1.0,
        .cullMode = .{
            .back = true,
        },
        .frontFace = frontFace,
        .depthBiasEnable = false,
        .depthBiasConstantFactor = 0.0,
        .depthBiasClamp = 0.0,
        .depthBiasSlopeFactor = 0.0,
    };

    // --- Multisampling.

    const multisampling = l0vk.VkPipelineMultisampleStateCreateInfo{
        .sampleShadingEnable = false,
        .rasterizationSamples = .VK_SAMPLE_COUNT_1_BIT,
        .minSampleShading = 1.0,
        .alphaToCoverageEnable = false,
        .alphaToOneEnable = false,
    };

    // --- Color blending.

    const color_blend_attachment = l0vk.VkPipelineColorBlendAttachmentState{
        .colorWriteMask = .{ .r = true, .g = true, .b = true, .a = true },
        .blendEnable = false,

        .srcColorBlendFactor = .one,
        .dstColorBlendFactor = .zero,
        .colorBlendOp = .add,
        .srcAlphaBlendFactor = .one,
        .dstAlphaBlendFactor = .zero,
        .alphaBlendOp = .add,
    };

    const color_blending = l0vk.VkPipelineColorBlendStateCreateInfo{
        .logicOpEnable = false,
        .logicOp = .copy,
        .attachments = &[_]l0vk.VkPipelineColorBlendAttachmentState{color_blend_attachment},
        .blendConstants = [_]f32{
            0.0,
            0.0,
            0.0,
            0.0,
        },
    };

    // -- Depth stencil.

    var depth_stencil_state: l0vk.VkPipelineDepthStencilStateCreateInfo = undefined;
    var pDepthStencilState: ?*const l0vk.VkPipelineDepthStencilStateCreateInfo = null;
    if (create_info.depth_test_enabled) {
        depth_stencil_state = l0vk.VkPipelineDepthStencilStateCreateInfo{
            .depthTestEnable = true,
            .depthWriteEnable = true,
            .depthCompareOp = l0vk.VkCompareOp.less_or_equal,
            .depthBoundsTestEnable = false,
            .minDepthBounds = 0.0,
            .maxDepthBounds = 1.0,
            .stencilTestEnable = false,
            .front = std.mem.zeroes(l0vk.VkStencilOpState),
            .back = std.mem.zeroes(l0vk.VkStencilOpState),
        };
        pDepthStencilState = &depth_stencil_state;
    }

    // -- Pipeline.

    // TODO: better error handling
    const renderpass = system.renderpass_system.get_renderpass_from_name(create_info.renderpass_name) orelse unreachable;

    var pipeline_rendering_create_info: l0vk.VkPipelineRenderingCreateInfo = undefined;
    var pipeline_pNext: ?*const l0vk.VkPipelineRenderingCreateInfo = undefined;
    var pipeline_renderpass: l0vk.VkRenderPass = undefined;
    var color_attachment_formats = [1]l0vk.VkFormat{undefined};
    var depth_attachment_format: l0vk.VkFormat = undefined;
    switch (renderpass.*) {
        .dynamic => {
            color_attachment_formats[0] = renderpass.dynamic.attachments.getPtr("color").?.format;
            depth_attachment_format = if (renderpass.dynamic.attachments.getPtr("depth")) |depth| depth.format else .undefined;
            pipeline_rendering_create_info = l0vk.VkPipelineRenderingCreateInfo{
                .colorAttachmentCount = 1,
                .pColorAttachmentFormats = &color_attachment_formats,
                .depthAttachmentFormat = depth_attachment_format,
                .stencilAttachmentFormat = .undefined,
            };

            pipeline_pNext = &pipeline_rendering_create_info;
            pipeline_renderpass = null;
        },
        .new => {
            color_attachment_formats[0] = renderpass.new.color_attachment_infos[0].format;
            const has_depth_attachment = renderpass.new.depth_attachments.len > 0;
            if (has_depth_attachment) {
                depth_attachment_format = renderpass.new.depth_attachment_infos[0].format;
            } else {
                depth_attachment_format = .undefined;
            }

            pipeline_rendering_create_info = l0vk.VkPipelineRenderingCreateInfo{
                .colorAttachmentCount = 1,
                .pColorAttachmentFormats = &color_attachment_formats,
                .depthAttachmentFormat = depth_attachment_format,
                .stencilAttachmentFormat = .undefined,
            };

            pipeline_pNext = &pipeline_rendering_create_info;
            pipeline_renderpass = null;
        },
        .static => {
            pipeline_pNext = null;
            pipeline_renderpass = renderpass.static.render_pass;
        },
    }

    const pipeline_info = l0vk.VkGraphicsPipelineCreateInfo{
        .pNext = pipeline_pNext,
        .flags = .{},
        .stages = &shader_stages,

        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &input_assembly,
        .pTessellationState = null,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pDepthStencilState = pDepthStencilState,
        .pColorBlendState = &color_blending,
        .pDynamicState = &dynamic_state,

        .layout = pipeline_layout,
        .renderPass = pipeline_renderpass,
        .subpass = 0,
        .basePipelineHandle = @ptrCast(l0vk.VK_NULL_HANDLE),
        .basePipelineIndex = -1,
    };

    const pipelines = try l0vk.vkCreateGraphicsPipelines(
        allocator,
        system.logical_device,
        @ptrCast(l0vk.VK_NULL_HANDLE),
        &[_]l0vk.VkGraphicsPipelineCreateInfo{pipeline_info},
        null,
    );
    defer allocator.free(pipelines);

    // ---

    l0vk.vkDestroyShaderModule(system.logical_device, vert_shader_module, null);
    l0vk.vkDestroyShaderModule(system.logical_device, frag_shader_module, null);

    return .{
        .pipeline = pipelines[0],
        .pipeline_layout = pipeline_layout,
    };
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

fn create_shader_module(device: l0vk.VkDevice, code: []const u8) !l0vk.VkShaderModule {
    const shader_module_create_info = l0vk.VkShaderModuleCreateInfo{
        .codeSize = @intCast(code.len),
        .pCode = @ptrCast(@alignCast(code.ptr)),
    };

    const shader_module = try l0vk.vkCreateShaderModule(device, &shader_module_create_info, null);

    return shader_module;
}
