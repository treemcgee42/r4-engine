const std = @import("std");
const PipelineInfo = @import("../pipeline.zig").PipelineInfo;
const VulkanSystem = @import("./VulkanSystem.zig");
const VulkanError = VulkanSystem.VulkanError;
const l0vk = @import("../layer0/vulkan/vulkan.zig");
const Renderer = @import("../Renderer.zig");
const VirtualPipeline = @import("../pipeline.zig").Pipeline;
const buffer = @import("./buffer.zig");
const Vertex = @import("../../../main.zig").Vertex;

pub const Pipeline = l0vk.VkPipeline;

pub const PipelineSystem = struct {
    pipelines: std.StringHashMap(l0vk.VkPipeline),

    pub fn init(allocator: std.mem.Allocator) PipelineSystem {
        const pipelines = std.StringHashMap(l0vk.VkPipeline).init(allocator);

        return .{
            .pipelines = pipelines,
        };
    }

    pub fn deinit(self: *PipelineSystem, system: *VulkanSystem) void {
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

    pub fn query(
        self: *PipelineSystem,
        renderer: *Renderer,
        virtual_pipeline: *const VirtualPipeline,
        renderpass: l0vk.VkRenderPass,
    ) !l0vk.VkPipeline {
        // --- Try to find in cache.

        const lookup_result = self.pipelines.get(virtual_pipeline.name);
        if (lookup_result != null) {
            return lookup_result.?;
        }

        // --- Construct it.

        const pipeline = try build_pipeline(renderer, virtual_pipeline, renderpass);
        try self.pipelines.put(virtual_pipeline.name, pipeline);

        return pipeline;
    }
};

pub fn build_pipeline(
    renderer: *Renderer,
    virtual_pipeline: *const VirtualPipeline,
    renderpass: l0vk.VkRenderPass,
) !l0vk.VkPipeline {
    const allocator = renderer.allocator;
    var system = renderer.system;

    const pipeline_layout_info = l0vk.VkPipelineLayoutCreateInfo{};
    const pipeline_layout = try l0vk.vkCreatePipelineLayout(
        system.logical_device,
        &pipeline_layout_info,
        null,
    );

    // ---

    const vert_shader_code = try read_file(virtual_pipeline.vertex_shader_filename, allocator);
    defer allocator.free(vert_shader_code);
    const frag_shader_code = try read_file(virtual_pipeline.fragment_shader_filename, allocator);
    defer allocator.free(frag_shader_code);

    const vert_shader_module = try create_shader_module(system.logical_device, vert_shader_code);
    const frag_shader_module = try create_shader_module(system.logical_device, frag_shader_code);

    // ---

    var vert_shader_stage_pipeline_create_info = l0vk.VkPipelineShaderStageCreateInfo{
        .stage = l0vk.VkShaderStageFlags.Bits.vertex,
        .module = vert_shader_module,
        .pName = "main",
    };

    var frag_shader_stage_pipeline_create_info = l0vk.VkPipelineShaderStageCreateInfo{
        .stage = l0vk.VkShaderStageFlags.Bits.fragment,
        .module = frag_shader_module,
        .pName = "main",
    };

    const shader_stages = [_]l0vk.VkPipelineShaderStageCreateInfo{
        vert_shader_stage_pipeline_create_info,
        frag_shader_stage_pipeline_create_info,
    };

    // --- Input assembly.

    const binding_description = buffer.get_binding_description(Vertex);
    const attribute_descriptions = try buffer.get_attribute_descriptions(
        allocator,
        Vertex,
    );
    defer allocator.free(attribute_descriptions);

    const vertex_input_info = l0vk.VkPipelineVertexInputStateCreateInfo{
        .vertex_binding_descriptions = &[_]l0vk.VkVertexInputBindingDescription{
            binding_description,
        },
        .vertex_attribute_descriptions = attribute_descriptions,
    };

    const topology = switch (virtual_pipeline.topology) {
        .triangle_list => l0vk.VkPrimitiveTopology.triangle_list,
    };

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

    const frontFace = switch (virtual_pipeline.front_face_orientation) {
        .clockwise => l0vk.VkFrontFace.clockwise,
        .counter_clockwise => l0vk.VkFrontFace.counter_clockwise,
    };

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

    // -- Pipeline.

    const pipeline_info = l0vk.VkGraphicsPipelineCreateInfo{
        .pNext = null,
        .flags = .{},
        .stages = &shader_stages,

        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &input_assembly,
        .pTessellationState = null,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pDepthStencilState = null,
        .pColorBlendState = &color_blending,
        .pDynamicState = &dynamic_state,

        .layout = pipeline_layout,
        .renderPass = renderpass,
        .subpass = 0,
        .basePipelineHandle = @ptrCast(l0vk.VK_NULL_HANDLE),
        .basePipelineIndex = -1,
    };

    var pipelines = try l0vk.vkCreateGraphicsPipelines(
        allocator,
        system.logical_device,
        @ptrCast(l0vk.VK_NULL_HANDLE),
        &[_]l0vk.VkGraphicsPipelineCreateInfo{pipeline_info},
        null,
    );
    defer allocator.free(pipelines);

    // ---

    // TODO: can this be destroyed here?
    l0vk.vkDestroyPipelineLayout(system.logical_device, pipeline_layout, null);

    l0vk.vkDestroyShaderModule(system.logical_device, vert_shader_module, null);
    l0vk.vkDestroyShaderModule(system.logical_device, frag_shader_module, null);

    return pipelines[0];
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
