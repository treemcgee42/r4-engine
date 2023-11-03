const l0vk = @import("./vulkan.zig");
const vulkan = @import("vulkan");

pub const VkShaderStageFlags = packed struct(u32) {
    vertex: bool = false,
    tessellation_control: bool = false,
    tessellation_evaluation: bool = false,
    geometry: bool = false,

    fragment: bool = false,
    compute: bool = false,
    _: u2 = 0,

    _a: u24 = 0,

    pub const Bits = enum(c_uint) {
        vertex = 0x00000001,
        tessellation_control = 0x00000002,
        tessellation_evaluation = 0x00000004,
        geometry = 0x00000008,

        fragment = 0x00000010,
        compute = 0x00000020,
    };
};

pub const VkShaderModule = vulkan.VkShaderModule;

pub const VkShaderModuleCreateInfo = struct {
    pNext: ?*const anyopaque = null,
    codeSize: usize,
    pCode: [*c]const u32,

    pub fn to_vulkan_ty(self: VkShaderModuleCreateInfo) vulkan.VkShaderModuleCreateInfo {
        return vulkan.VkShaderModuleCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .codeSize = self.codeSize,
            .pCode = self.pCode,
            .pNext = self.pNext,
            .flags = 0,
        };
    }
};

pub const vkCreateShaderModuleError = error{
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
    VK_ERROR_INVALID_SHADER_NV,
};

pub fn vkCreateShaderModule(
    device: l0vk.VkDevice,
    pCreateInfo: *const VkShaderModuleCreateInfo,
    pAllocator: [*c]const l0vk.VkAllocationCallbacks,
) vkCreateShaderModuleError!VkShaderModule {
    var create_info = pCreateInfo.to_vulkan_ty();

    var shader_module: vulkan.VkShaderModule = undefined;
    const result = vulkan.vkCreateShaderModule(device, &create_info, pAllocator, &shader_module);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkCreateShaderModuleError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkCreateShaderModuleError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_INVALID_SHADER_NV => return vkCreateShaderModuleError.VK_ERROR_INVALID_SHADER_NV,
            else => unreachable,
        }
    }

    return shader_module;
}

pub inline fn vkDestroyShaderModule(
    device: l0vk.VkDevice,
    shaderModule: VkShaderModule,
    pAllocator: [*c]const l0vk.VkAllocationCallbacks,
) void {
    vulkan.vkDestroyShaderModule(device, shaderModule, pAllocator);
}
