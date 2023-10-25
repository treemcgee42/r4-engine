const std = @import("std");
const vulkan = @import("vulkan");
const l0vk = @import("./vulkan.zig");

pub const VkCommandPoolCreateFlags = packed struct(u32) {
    transient: bool = false,
    reset_command_buffer: bool = false,
    // Provided by VK_VERSION_1_1
    protected: bool = false,
    _: u1 = 0,

    _a: u28 = 0,

    pub const Bits = enum(c_uint) {
        transient = 0x00000001,
        reset_command_buffer = 0x00000002,
        // Provided by VK_VERSION_1_1
        protected = 0x00000004,
    };
};

pub const VkCommandPoolCreateInfo = struct {
    pNext: ?*const anyopaque = null,
    flags: VkCommandPoolCreateFlags = .{},
    queueFamilyIndex: u32 = 0,

    pub fn to_vulkan_ty(self: VkCommandPoolCreateInfo) vulkan.VkCommandPoolCreateInfo {
        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .pNext = self.pNext,
            .flags = @bitCast(self.flags),
            .queueFamilyIndex = self.queueFamilyIndex,
        };
    }
};

pub const VkCommandPool = vulkan.VkCommandPool;

pub const vkCreateCommandPoolError = error{
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
};

pub fn vkCreateCommandPool(
    device: l0vk.VkDevice,
    pCreateInfo: *const VkCommandPoolCreateInfo,
    pAllactor: ?*const l0vk.VkAllocationCallbacks,
) vkCreateCommandPoolError!VkCommandPool {
    var pool_info = pCreateInfo.to_vulkan_ty();

    var command_pool: vulkan.VkCommandPool = undefined;
    const result = vulkan.vkCreateCommandPool(
        device,
        &pool_info,
        pAllactor,
        &command_pool,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkCreateCommandPoolError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkCreateCommandPoolError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            else => unreachable,
        }
    }

    return command_pool;
}

pub inline fn vkDestroyCommandPool(
    device: l0vk.VkDevice,
    commandPool: VkCommandPool,
    pAllocator: ?*const l0vk.VkAllocationCallbacks,
) void {
    vulkan.vkDestroyCommandPool(device, commandPool, pAllocator);
}

pub const VkCommandBufferUsageFlags = packed struct(u32) {
    one_time_submit: bool = false,
    render_pass_continue: bool = false,
    simultaneous_use: bool = false,
    _: u1 = 0,

    _a: u28 = 0,

    pub const Bits = enum(c_uint) {
        one_time_submit = 0x00000001,
        render_pass_continue = 0x00000002,
        simultaneous_use = 0x00000004,
    };
};

pub const VkCommandBufferInheritanceInfo = struct {
    pNext: ?*const anyopaque = null,
    renderPass: l0vk.VkRenderPass,
    subpass: u32,
    framebuffer: l0vk.VkFramebuffer,
    occlusionQueryEnable: bool,
    queryFlags: l0vk.VkQueryControlFlags = .{},
    pipelineStatistics: l0vk.VkQueryPipelineStatisticFlags = .{},

    pub fn to_vulkan_ty(self: VkCommandBufferInheritanceInfo) vulkan.VkCommandBufferInheritanceInfo {
        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO,
            .pNext = self.pNext,
            .renderPass = self.renderPass,
            .subpass = self.subpass,
            .framebuffer = self.framebuffer,
            .occlusionQueryEnable = @intFromBool(self.occlusionQueryEnable),
            .queryFlags = @bitCast(self.queryFlags),
            .pipelineStatistics = @bitCast(self.pipelineStatistics),
        };
    }
};

pub const VkCommandBufferBeginInfo = struct {
    pNext: ?*const anyopaque = null,
    flags: VkCommandBufferUsageFlags = .{},
    pInheritanceInfo: ?*const VkCommandBufferInheritanceInfo = null,

    pub fn to_vulkan_ty(self: *const VkCommandBufferBeginInfo) vulkan.VkCommandBufferBeginInfo {
        var inheritance_info: vulkan.VkCommandBufferInheritanceInfo = undefined;
        var p_inheritance_info: ?*const vulkan.VkCommandBufferInheritanceInfo = null;
        if (self.pInheritanceInfo) |info| {
            inheritance_info = info.to_vulkan_ty();
            p_inheritance_info = &inheritance_info;
        }

        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .pNext = self.pNext,
            .flags = @bitCast(self.flags),
            .pInheritanceInfo = p_inheritance_info,
        };
    }
};

pub const VkCommandBuffer = vulkan.VkCommandBuffer;

pub const vkBeginCommandBufferError = error{
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
};

pub fn vkBeginCommandBuffer(
    commandBuffer: VkCommandBuffer,
    pBeginInfo: *const VkCommandBufferBeginInfo,
) vkBeginCommandBufferError!void {
    const begin_info = pBeginInfo.to_vulkan_ty();
    var result = vulkan.vkBeginCommandBuffer(commandBuffer, &begin_info);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkBeginCommandBufferError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkBeginCommandBufferError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            else => unreachable,
        }
    }
}

pub const vkEndCommandBufferError = error{
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
};

pub fn vkEndCommandBuffer(command_buffer: VkCommandBuffer) !void {
    var result = vulkan.vkEndCommandBuffer(command_buffer);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkEndCommandBufferError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkEndCommandBufferError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            else => unreachable,
        }
    }
}

pub const VkCommandBufferLevel = enum(c_uint) {
    primary = 0,
    secondary = 1,
};

pub const VkCommandBufferAllocateInfo = struct {
    pNext: ?*const anyopaque = null,
    commandPool: VkCommandPool,
    level: VkCommandBufferLevel,
    commandBufferCount: u32,

    pub fn to_vulkan_ty(self: *const VkCommandBufferAllocateInfo) vulkan.VkCommandBufferAllocateInfo {
        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .pNext = self.pNext,
            .commandPool = self.commandPool,
            .level = @intFromEnum(self.level),
            .commandBufferCount = self.commandBufferCount,
        };
    }
};

pub const vkAllocateCommandBuffersError = error{
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,

    OutOfMemory,
};

pub fn vkAllocateCommandBuffers(
    allocator: std.mem.Allocator,
    device: l0vk.VkDevice,
    pAllocateInfo: *const VkCommandBufferAllocateInfo,
) vkAllocateCommandBuffersError![]VkCommandBuffer {
    var command_buffers = try allocator.alloc(VkCommandBuffer, pAllocateInfo.commandBufferCount);
    errdefer allocator.free(command_buffers);

    const alloc_info = pAllocateInfo.to_vulkan_ty();

    const result = vulkan.vkAllocateCommandBuffers(device, &alloc_info, command_buffers.ptr);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkAllocateCommandBuffersError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkAllocateCommandBuffersError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            else => unreachable,
        }
    }

    return command_buffers;
}
