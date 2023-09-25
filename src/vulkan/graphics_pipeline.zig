const std = @import("std");
const vulkan = @import("../c.zig").vulkan;

const VulkanError = @import("./vulkan.zig").VulkanError;

const GraphicsPipeline = @This();

pub fn init(allocator_: std.mem.Allocator, device: vulkan.VkDevice) VulkanError!GraphicsPipeline {
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
    _ = shader_stages;

    // ---

    vulkan.vkDestroyShaderModule(device, vert_shader_module, null);
    vulkan.vkDestroyShaderModule(device, frag_shader_module, null);

    return .{};
}

pub fn deinit(self: GraphicsPipeline) void {
    _ = self;
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
