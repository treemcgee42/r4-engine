const std = @import("std");
const vulkan = @import("vulkan");
const l0vk = @import("./vulkan.zig");

// --- Attachment.

pub const VkAttachmentDescriptionFlags = packed struct(u32) {
    may_alias: bool = false,
    _: u3 = 0,

    _a: u28 = 0,

    pub const Bits = enum(c_uint) {
        may_alias = 0x00000001,
    };
};

pub const VkAttachmentLoadOp = enum(c_uint) {
    load = 0,
    clear = 1,
    dont_care = 2,

    non_ext = 1000400000,
};

pub const VkAttachmentStoreOp = enum(c_uint) {
    store = 0,
    dont_care = 1,

    non_ext = 1000301000,
};

pub const VkAttachmentDescription = struct {
    flags: VkAttachmentDescriptionFlags = .{},
    format: l0vk.VkFormat,
    samples: l0vk.VkSampleCountFlags.Bits,
    loadOp: VkAttachmentLoadOp,
    storeOp: VkAttachmentStoreOp,
    stencilLoadOp: VkAttachmentLoadOp,
    stencilStoreOp: VkAttachmentStoreOp,
    initialLayout: l0vk.VkImageLayout,
    finalLayout: l0vk.VkImageLayout,

    pub fn to_vulkan_ty(self: *const VkAttachmentDescription) vulkan.VkAttachmentDescription {
        return vulkan.VkAttachmentDescription{
            .flags = @bitCast(self.flags),
            .format = @intFromEnum(self.format),
            .samples = @intFromEnum(self.samples),
            .loadOp = @intFromEnum(self.loadOp),
            .storeOp = @intFromEnum(self.storeOp),
            .stencilLoadOp = @intFromEnum(self.stencilLoadOp),
            .stencilStoreOp = @intFromEnum(self.stencilStoreOp),
            .initialLayout = @intFromEnum(self.initialLayout),
            .finalLayout = @intFromEnum(self.finalLayout),
        };
    }
};

pub const VkAttachmentReference = struct {
    attachment: u32,
    layout: l0vk.VkImageLayout,

    pub fn to_vulkan_ty(self: *const VkAttachmentReference) vulkan.VkAttachmentReference {
        return vulkan.VkAttachmentReference{
            .attachment = self.attachment,
            .layout = @intFromEnum(self.layout),
        };
    }
};

// --- Subpass.

pub const VkSubpassDescriptionFlags = packed struct(u32) {
    per_view_attributes: bool = false,
    per_view_position_x_only: bool = false,
    fragment_region_qcom: bool = false,
    shader_resolve_qcom: bool = false,

    rasterization_order_attachment_color_access: bool = false,
    rasterization_order_attachment_depth_access: bool = false,
    rasterization_order_attachment_stencil_access: bool = false,
    legacy_dithering: bool = false,

    _: u24 = 0,

    pub const Bits = enum(c_uint) {
        per_view_attributes = 0x00000001,
        per_view_position_x_only = 0x00000002,
        fragment_region_qcom = 0x00000004,
        shader_resolve_qcom = 0x00000008,

        rasterization_order_attachment_color_access = 0x00000010,
        rasterization_order_attachment_depth_access = 0x00000020,
        rasterization_order_attachment_stencil_access = 0x00000040,
        legacy_dithering = 0x00000080,
    };
};

pub const VkSubpassDescription = struct {
    flags: VkSubpassDescriptionFlags = .{},
    pipelineBindPoint: l0vk.VkPipelineBindPoint,
    inputAttachments: []const VkAttachmentReference,
    colorAttachments: []const VkAttachmentReference,
    resolveAttachments: []const VkAttachmentReference,
    pDepthStencilAttachment: ?*const VkAttachmentReference,
    preserveAttachments: []const u32,

    pub fn to_vulkan_ty(self: *const VkSubpassDescription, allocator: std.mem.Allocator) vulkan.VkSubpassDescription {
        var input_attachments = allocator.alloc(vulkan.VkAttachmentReference, self.inputAttachments.len) catch {
            @panic("fba ran out of memory");
        };
        var i: usize = 0;
        while (i < self.inputAttachments.len) : (i += 1) {
            input_attachments[i] = self.inputAttachments[i].to_vulkan_ty();
        }

        var color_attachments = allocator.alloc(vulkan.VkAttachmentReference, self.colorAttachments.len) catch {
            @panic("fba ran out of memory");
        };
        i = 0;
        while (i < self.colorAttachments.len) : (i += 1) {
            color_attachments[i] = self.colorAttachments[i].to_vulkan_ty();
        }

        var resolve_attachments = allocator.alloc(vulkan.VkAttachmentReference, self.resolveAttachments.len) catch {
            @panic("fba ran out of memory");
        };
        i = 0;
        while (i < self.resolveAttachments.len) : (i += 1) {
            resolve_attachments[i] = self.resolveAttachments[i].to_vulkan_ty();
        }
        // Warning: if we don't explicitly set this to null, the Vulkan validation layer will segfault.
        var p_resolve_attachments: [*c]vulkan.VkAttachmentReference = null;
        if (resolve_attachments.len > 0) {
            p_resolve_attachments = resolve_attachments[0..].ptr;
        }

        var p_depth_stencil_attachment: ?*vulkan.VkAttachmentReference = null;
        if (self.pDepthStencilAttachment != null) {
            p_depth_stencil_attachment = allocator.create(vulkan.VkAttachmentReference) catch {
                @panic("fba ran out of memory");
            };
            p_depth_stencil_attachment.?.* = self.pDepthStencilAttachment.?.to_vulkan_ty();
        }

        return vulkan.VkSubpassDescription{
            .flags = @bitCast(self.flags),
            .pipelineBindPoint = @intFromEnum(self.pipelineBindPoint),

            .inputAttachmentCount = @intCast(self.inputAttachments.len),
            .pInputAttachments = input_attachments[0..].ptr,

            .colorAttachmentCount = @intCast(self.colorAttachments.len),
            .pColorAttachments = color_attachments[0..].ptr,

            .pResolveAttachments = p_resolve_attachments,

            .pDepthStencilAttachment = p_depth_stencil_attachment,

            .preserveAttachmentCount = @intCast(self.preserveAttachments.len),
            .pPreserveAttachments = self.preserveAttachments.ptr,
        };
    }
};

pub const VkAccessFlags = packed struct(u32) {
    indirect_command_read: bool = false,
    index_read: bool = false,
    vertex_attribute_read: bool = false,
    uniform_read: bool = false,

    input_attachment_read: bool = false,
    shader_read: bool = false,
    shader_write: bool = false,
    color_attachment_read: bool = false,

    color_attachment_write: bool = false,
    depth_stencil_attachment_read: bool = false,
    depth_stencil_attachment_write: bool = false,
    transfer_read: bool = false,

    transfer_write: bool = false,
    host_read: bool = false,
    host_write: bool = false,
    memory_read: bool = false,

    memory_write: bool = false,
    _: u3 = 0,

    _a: u12 = 0,

    pub const Bits = enum(c_uint) {
        indirect_command_read = 0x00000001,
        index_read = 0x00000002,
        vertex_attribute_read = 0x00000004,
        uniform_read = 0x00000008,

        input_attachment_read = 0x00000010,
        shader_read = 0x00000020,
        shader_write = 0x00000040,
        color_attachment_read = 0x00000080,

        color_attachment_write = 0x00000100,
        depth_stencil_attachment_read = 0x00000200,
        depth_stencil_attachment_write = 0x00000400,
        transfer_read = 0x00000800,

        transfer_write = 0x00001000,
        host_read = 0x00002000,
        host_write = 0x00004000,
        memory_read = 0x00008000,

        memory_write = 0x00010000,
    };
};

pub const VkDependencyFlags = packed struct(u32) {
    by_region: bool = false,
    view_local: bool = false,
    device_group: bool = false,
    feedback_loop: bool = false,

    _: u28 = 0,

    pub const Bits = enum(c_uint) {
        by_region = 0x00000001,
        view_local = 0x00000002,
        device_group = 0x00000004,
        feedback_loop = 0x00000008,
    };
};

pub const VK_SUBPASS_EXTERNAL = vulkan.VK_SUBPASS_EXTERNAL;

pub const VkSubpassDependency = struct {
    srcSubpass: u32,
    dstSubpass: u32,
    srcStageMask: l0vk.VkPipelineStageFlags = .{},
    dstStageMask: l0vk.VkPipelineStageFlags = .{},
    srcAccessMask: VkAccessFlags = .{},
    dstAccessMask: VkAccessFlags = .{},
    dependencyFlags: VkDependencyFlags = .{},

    pub fn to_vulkan_ty(self: *const VkSubpassDependency) vulkan.VkSubpassDependency {
        return vulkan.VkSubpassDependency{
            .srcSubpass = self.srcSubpass,
            .dstSubpass = self.dstSubpass,
            .srcStageMask = @bitCast(self.srcStageMask),
            .dstStageMask = @bitCast(self.dstStageMask),
            .srcAccessMask = @bitCast(self.srcAccessMask),
            .dstAccessMask = @bitCast(self.dstAccessMask),
            .dependencyFlags = @bitCast(self.dependencyFlags),
        };
    }
};

pub const VkSubpassContents = enum(c_uint) {
    _inline = 0,
    secondary_command_buffers = 1,
};

// --- RenderPass.

pub const VkRenderPassCreateFlags = packed struct(u32) {
    transform_qcom: bool = false,
    _: u31 = 0,

    pub const Bits = enum(c_uint) {
        transform_qcom = 0x00000002,
    };
};

pub const VkRenderPassCreateInfo = struct {
    pNext: ?*const anyopaque = null,
    flags: VkRenderPassCreateFlags = .{},
    attachments: []const VkAttachmentDescription,
    subpasses: []const VkSubpassDescription,
    dependencies: []const VkSubpassDependency,

    pub fn to_vulkan_ty(self: *const VkRenderPassCreateInfo, allocator: std.mem.Allocator) vulkan.VkRenderPassCreateInfo {
        const attachments = allocator.alloc(vulkan.VkAttachmentDescription, self.attachments.len) catch {
            @panic("fba ran out of memory");
        };
        const subpasses = allocator.alloc(vulkan.VkSubpassDescription, self.subpasses.len) catch {
            @panic("fba ran out of memory");
        };
        const dependencies = allocator.alloc(vulkan.VkSubpassDependency, self.dependencies.len) catch {
            @panic("fba ran out of memory");
        };

        var i: usize = 0;
        while (i < self.attachments.len) : (i += 1) {
            attachments[i] = self.attachments[i].to_vulkan_ty();
        }
        i = 0;
        while (i < self.subpasses.len) : (i += 1) {
            subpasses[i] = self.subpasses[i].to_vulkan_ty(allocator);
        }
        i = 0;
        while (i < self.dependencies.len) : (i += 1) {
            dependencies[i] = self.dependencies[i].to_vulkan_ty();
        }

        return vulkan.VkRenderPassCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,

            .attachmentCount = @intCast(self.attachments.len),
            .pAttachments = attachments[0..].ptr,

            .subpassCount = @intCast(self.subpasses.len),
            .pSubpasses = subpasses[0..].ptr,

            .dependencyCount = @intCast(self.dependencies.len),
            .pDependencies = dependencies[0..].ptr,

            .pNext = self.pNext,
            .flags = @bitCast(self.flags),
        };
    }
};

pub const vkCreateRenderPassError = error{
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
};

pub fn vkCreateRenderPass(
    device: l0vk.VkDevice,
    pCreateInfo: *const VkRenderPassCreateInfo,
    pAllocator: [*c]const l0vk.VkAllocationCallbacks,
) vkCreateRenderPassError!VkRenderPass {
    var buf: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();

    const create_info = pCreateInfo.to_vulkan_ty(allocator);

    var renderpass: VkRenderPass = undefined;
    const result = vulkan.vkCreateRenderPass(
        device,
        &create_info,
        pAllocator,
        &renderpass,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkCreateRenderPassError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkCreateRenderPassError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            else => unreachable,
        }
    }

    return renderpass;
}

pub inline fn vkDestroyRenderPass(
    device: l0vk.VkDevice,
    renderPass: VkRenderPass,
    pAllocator: [*c]const l0vk.VkAllocationCallbacks,
) void {
    vulkan.vkDestroyRenderPass(device, renderPass, pAllocator);
}

pub const VkRenderPass = vulkan.VkRenderPass;

pub const VkClearColorValue = vulkan.VkClearColorValue;

pub const VkClearDepthStencilValue = vulkan.VkClearDepthStencilValue;

pub const VkClearValue = vulkan.VkClearValue;

pub const VkRenderPassBeginInfo = struct {
    pNext: ?*const anyopaque = null,
    renderPass: VkRenderPass,
    framebuffer: VkFramebuffer,
    renderArea: l0vk.VkRect2D,
    clearValues: []const VkClearValue,

    pub fn to_vulkan_ty(self: *const VkRenderPassBeginInfo) vulkan.VkRenderPassBeginInfo {
        return vulkan.VkRenderPassBeginInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .pNext = self.pNext,
            .renderPass = self.renderPass,
            .framebuffer = self.framebuffer,
            .renderArea = self.renderArea,
            .clearValueCount = @intCast(self.clearValues.len),
            .pClearValues = self.clearValues.ptr,
        };
    }
};

pub fn vkCmdBeginRenderPass(
    commandBuffer: l0vk.VkCommandBuffer,
    pRenderPassBegin: *const VkRenderPassBeginInfo,
    contents: VkSubpassContents,
) void {
    const render_pass_begin = pRenderPassBegin.to_vulkan_ty();
    vulkan.vkCmdBeginRenderPass(
        commandBuffer,
        &render_pass_begin,
        @intFromEnum(contents),
    );
}

pub inline fn vkCmdEndRenderPass(commandBuffer: l0vk.VkCommandBuffer) void {
    vulkan.vkCmdEndRenderPass(commandBuffer);
}

// --- Framebuffer.

pub const VkFramebufferCreateFlags = packed struct(u32) {
    imageless: bool = false,
    _: u31 = 0,

    pub const Bits = enum(c_uint) {
        imageless = 0x00000001,
    };
};

pub const VkFramebufferCreateInfo = struct {
    pNext: ?*const anyopaque = null,
    flags: VkFramebufferCreateFlags = .{},
    renderPass: VkRenderPass,
    attachments: []const l0vk.VkImageView,
    width: u32,
    height: u32,
    layers: u32,

    pub fn to_vulkan_ty(self: *const VkFramebufferCreateInfo) vulkan.VkFramebufferCreateInfo {
        return vulkan.VkFramebufferCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .pNext = self.pNext,
            .flags = @bitCast(self.flags),
            .renderPass = self.renderPass,
            .attachmentCount = @intCast(self.attachments.len),
            .pAttachments = self.attachments.ptr,
            .width = self.width,
            .height = self.height,
            .layers = self.layers,
        };
    }
};

pub const vkCreateFramebufferError = error{
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
};

pub fn vkCreateFramebuffer(
    device: l0vk.VkDevice,
    pCreateInfo: *const VkFramebufferCreateInfo,
    pAllocator: [*c]const l0vk.VkAllocationCallbacks,
) vkCreateFramebufferError!VkFramebuffer {
    const create_info = pCreateInfo.to_vulkan_ty();

    var framebuffer: vulkan.VkFramebuffer = undefined;
    const result = vulkan.vkCreateFramebuffer(device, &create_info, pAllocator, &framebuffer);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkCreateFramebufferError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkCreateFramebufferError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            else => unreachable,
        }
    }

    return framebuffer;
}

pub inline fn vkDestroyFramebuffer(
    device: l0vk.VkDevice,
    framebuffer: VkFramebuffer,
    pAllocator: [*c]const l0vk.VkAllocationCallbacks,
) void {
    vulkan.vkDestroyFramebuffer(device, framebuffer, pAllocator);
}

pub const VkFramebuffer = vulkan.VkFramebuffer;

// --- DescriptorPool.

pub const VkDescriptorType = enum(c_uint) {
    sampler = 0,
    combined_image_sampler = 1,
    sampled_image = 2,
    storage_image = 3,
    uniform_texel_buffer = 4,
    storage_texel_buffer = 5,
    uniform_buffer = 6,
    storage_buffer = 7,
    uniform_buffer_dynamic = 8,
    storage_buffer_dynamic = 9,
    input_attachment = 10,
};

pub const VkDescriptorPoolSize = struct {
    type: VkDescriptorType,
    descriptorCount: u32,

    pub fn to_vulkan_ty(self: *const VkDescriptorPoolSize) vulkan.VkDescriptorPoolSize {
        return vulkan.VkDescriptorPoolSize{
            .type = @intFromEnum(self.type),
            .descriptorCount = self.descriptorCount,
        };
    }
};

pub const VkDescriptorPoolCreateFlags = packed struct(u32) {
    free_descriptor_set: bool = false,
    update_after_bind: bool = false,
    host_only: bool = false,
    allow_overallocation: bool = false,

    _: u28 = 0,

    pub const Bits = enum(c_uint) {
        free_descriptor_set = 0x00000001,
        update_after_bind = 0x00000002,
        host_only = 0x00000004,
        allow_overallocation = 0x00000008,
    };
};

pub const VkDescriptorPoolCreateInfo = struct {
    flags: VkDescriptorPoolCreateFlags = .{},
    pNext: ?*const anyopaque = null,
    maxSets: u32,
    poolSizes: []const VkDescriptorPoolSize,

    pub fn to_vulkan_ty(self: *const VkDescriptorPoolCreateInfo, allocator: std.mem.Allocator) vulkan.VkDescriptorPoolCreateInfo {
        var pool_sizes = allocator.alloc(vulkan.VkDescriptorPoolSize, self.poolSizes.len) catch {
            std.debug.print("fba ran out of memory\n", .{});
            unreachable;
        };
        var i: usize = 0;
        while (i < self.poolSizes.len) : (i += 1) {
            pool_sizes[i] = self.poolSizes[i].to_vulkan_ty();
        }

        return vulkan.VkDescriptorPoolCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .pNext = self.pNext,
            .flags = @bitCast(self.flags),
            .maxSets = self.maxSets,
            .poolSizeCount = @intCast(pool_sizes.len),
            .pPoolSizes = pool_sizes.ptr,
        };
    }
};

pub const vkCreateDescriptorPoolError = error{
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
    VK_ERROR_FRAGMENTATION_EXT,
};

pub fn vkCreateDescriptorPool(
    device: l0vk.VkDevice,
    pCreateInfo: *const VkDescriptorPoolCreateInfo,
    pAllocator: [*c]const l0vk.VkAllocationCallbacks,
) vkCreateDescriptorPoolError!VkDescriptorPool {
    var buffer: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const create_info = pCreateInfo.to_vulkan_ty(allocator);

    var descriptor_pool: vulkan.VkDescriptorPool = undefined;
    const result = vulkan.vkCreateDescriptorPool(device, &create_info, pAllocator, &descriptor_pool);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkCreateDescriptorPoolError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkCreateDescriptorPoolError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_FRAGMENTATION_EXT => return vkCreateDescriptorPoolError.VK_ERROR_FRAGMENTATION_EXT,
            else => unreachable,
        }
    }

    return descriptor_pool;
}

pub inline fn vkDestroyDescriptorPool(
    device: l0vk.VkDevice,
    descriptorPool: VkDescriptorPool,
    pAllocator: [*c]const l0vk.VkAllocationCallbacks,
) void {
    vulkan.vkDestroyDescriptorPool(device, descriptorPool, pAllocator);
}

pub const VkDescriptorPool = vulkan.VkDescriptorPool;
