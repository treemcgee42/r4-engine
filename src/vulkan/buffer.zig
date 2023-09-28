const c_string = @cImport({
    @cInclude("string.h");
});
const stb_image = @import("../c.zig").stb_image;
const std = @import("std");
const vulkan = @import("../c.zig").vulkan;
const VulkanError = @import("./vulkan.zig").VulkanError;
const Vertex = @import("../vertex.zig");
const cbuf = @import("./command_buffer.zig");

fn find_memory_type(
    physical_device: vulkan.VkPhysicalDevice,
    memory_type_filter: u32,
    properties: vulkan.VkMemoryPropertyFlags,
) VulkanError!u32 {
    var memory_properties: vulkan.VkPhysicalDeviceMemoryProperties = undefined;
    vulkan.vkGetPhysicalDeviceMemoryProperties(physical_device, &memory_properties);

    var i: u5 = 0;
    while (i < memory_properties.memoryTypeCount) : (i += 1) {
        if ((memory_type_filter & (@as(u32, @intCast(1)) << i) != 0) and (memory_properties.memoryTypes[i].propertyFlags & properties) == properties) {
            return i;
        }
    }

    return VulkanError.no_suitable_memory_type;
}

const Buffer = struct {
    len: usize,
    buffer: vulkan.VkBuffer,
    buffer_memory: vulkan.VkDeviceMemory,

    fn init(
        physical_device: vulkan.VkPhysicalDevice,
        device: vulkan.VkDevice,
        buffer_size: vulkan.VkDeviceSize,
        usage_flags: vulkan.VkBufferUsageFlags,
        property_flags: vulkan.VkMemoryPropertyFlags,
    ) VulkanError!Buffer {
        const buffer_info = vulkan.VkBufferCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = buffer_size,
            .usage = usage_flags,
            .sharingMode = vulkan.VK_SHARING_MODE_EXCLUSIVE,

            .pNext = null,
            .flags = 0,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        };

        var vertex_buffer: vulkan.VkBuffer = undefined;
        var result = vulkan.vkCreateBuffer(device, &buffer_info, null, &vertex_buffer);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS_KHR => return VulkanError.vk_error_invalid_opaque_capture_address_khr,
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }
        errdefer vulkan.vkDestroyBuffer(device, vertex_buffer, null);

        // --- Memory allocation.

        var memory_requirements: vulkan.VkMemoryRequirements = undefined;
        vulkan.vkGetBufferMemoryRequirements(device, vertex_buffer, &memory_requirements);

        const memory_type_index = try find_memory_type(
            physical_device,
            memory_requirements.memoryTypeBits,
            property_flags,
        );
        const alloc_info = vulkan.VkMemoryAllocateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = memory_requirements.size,
            .memoryTypeIndex = memory_type_index,

            .pNext = null,
        };

        var vertex_buffer_memory: vulkan.VkDeviceMemory = undefined;
        result = vulkan.vkAllocateMemory(device, &alloc_info, null, &vertex_buffer_memory);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }
        errdefer vulkan.vkFreeMemory(device, vertex_buffer_memory, null);

        // --- Bind memory.

        result = vulkan.vkBindBufferMemory(device, vertex_buffer, vertex_buffer_memory, 0);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }

        return .{
            .len = buffer_size,
            .buffer = vertex_buffer,
            .buffer_memory = vertex_buffer_memory,
        };
    }

    fn deinit(self: Buffer, device: vulkan.VkDevice) void {
        vulkan.vkDestroyBuffer(device, self.buffer, null);
        vulkan.vkFreeMemory(device, self.buffer_memory, null);
    }

    fn copy(
        device: vulkan.VkDevice,
        command_pool: vulkan.VkCommandPool,
        graphics_queue: vulkan.VkQueue,
        src: Buffer,
        dest: Buffer,
        buffer_size: vulkan.VkDeviceSize,
    ) VulkanError!void {
        var command_buffer = try cbuf.begin_single_time_commands(device, command_pool);

        const copy_region = vulkan.VkBufferCopy{
            .srcOffset = 0,
            .dstOffset = 0,
            .size = buffer_size,
        };

        vulkan.vkCmdCopyBuffer(command_buffer, src.buffer, dest.buffer, 1, &copy_region);

        try cbuf.end_single_time_commands(device, command_pool, graphics_queue, command_buffer);
    }
};

pub const VertexBuffer = struct {
    buffer: Buffer,

    pub fn init(
        physical_device: vulkan.VkPhysicalDevice,
        device: vulkan.VkDevice,
        command_pool: vulkan.VkCommandPool,
        graphics_queue: vulkan.VkQueue,
    ) VulkanError!VertexBuffer {
        const buffer_size = @sizeOf(Vertex.Vertex) * Vertex.vertices.len;

        // --- Staging buffer.

        const staging_buffer = try Buffer.init(
            physical_device,
            device,
            buffer_size,
            vulkan.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vulkan.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vulkan.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        );
        defer staging_buffer.deinit(device);

        // --- Copy data to staging buffer.

        var data: ?*anyopaque = undefined;
        var result = vulkan.vkMapMemory(device, staging_buffer.buffer_memory, 0, buffer_size, 0, &data);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }

        _ = c_string.memcpy(data, @ptrCast(Vertex.vertices[0..].ptr), @intCast(buffer_size));

        vulkan.vkUnmapMemory(device, staging_buffer.buffer_memory);

        // --- Create GPU local buffer.

        const buffer = try Buffer.init(
            physical_device,
            device,
            buffer_size,
            vulkan.VK_BUFFER_USAGE_TRANSFER_DST_BIT | vulkan.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            vulkan.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        );
        errdefer buffer.deinit(device);

        // --- Copy data from staging buffer to GPU local buffer.

        try Buffer.copy(device, command_pool, graphics_queue, staging_buffer, buffer, buffer_size);

        // ---

        return .{
            .buffer = buffer,
        };
    }

    pub fn deinit(self: VertexBuffer, device: vulkan.VkDevice) void {
        self.buffer.deinit(device);
    }
};

pub const IndexBuffer = struct {
    buffer: Buffer,
    len: usize,

    pub fn init(
        physical_device: vulkan.VkPhysicalDevice,
        device: vulkan.VkDevice,
        command_pool: vulkan.VkCommandPool,
        graphics_queue: vulkan.VkQueue,
    ) VulkanError!IndexBuffer {
        const buffer_size = @sizeOf(@TypeOf(Vertex.indices[0])) * Vertex.indices.len;

        // --- Staging buffer.

        const staging_buffer = try Buffer.init(
            physical_device,
            device,
            buffer_size,
            vulkan.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vulkan.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vulkan.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        );
        defer staging_buffer.deinit(device);

        // --- Copy data to staging buffer.

        var data: ?*anyopaque = undefined;
        var result = vulkan.vkMapMemory(device, staging_buffer.buffer_memory, 0, buffer_size, 0, &data);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }

        _ = c_string.memcpy(data, @ptrCast(Vertex.indices[0..].ptr), @intCast(buffer_size));

        vulkan.vkUnmapMemory(device, staging_buffer.buffer_memory);

        // --- Create GPU local buffer.

        const buffer = try Buffer.init(
            physical_device,
            device,
            buffer_size,
            vulkan.VK_BUFFER_USAGE_TRANSFER_DST_BIT | vulkan.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
            vulkan.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        );
        errdefer buffer.deinit(device);

        // --- Copy data from staging buffer to GPU local buffer.

        try Buffer.copy(device, command_pool, graphics_queue, staging_buffer, buffer, buffer_size);

        // ---

        return .{
            .buffer = buffer,
            .len = Vertex.indices.len,
        };
    }

    pub fn deinit(self: IndexBuffer, device: vulkan.VkDevice) void {
        self.buffer.deinit(device);
    }
};

pub const UniformBuffers = struct {
    allocator: std.mem.Allocator,
    buffers: []Buffer,
    buffers_mapped: []?*anyopaque,

    pub fn init(
        allocator: std.mem.Allocator,
        physical_device: vulkan.VkPhysicalDevice,
        device: vulkan.VkDevice,
        max_frames_in_flight: usize,
    ) VulkanError!UniformBuffers {
        var buffers = try allocator.alloc(Buffer, max_frames_in_flight);
        errdefer allocator.free(buffers);
        var buffers_mapped = try allocator.alloc(?*anyopaque, max_frames_in_flight);
        errdefer allocator.free(buffers_mapped);

        const buffer_size = @sizeOf(Vertex.UniformBufferObject);

        var i: usize = 0;
        while (i < max_frames_in_flight) : (i += 1) {
            // --- Create buffer.

            const buffer = try Buffer.init(
                physical_device,
                device,
                buffer_size,
                vulkan.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                vulkan.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vulkan.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            );
            errdefer buffer.deinit(device);

            buffers[i] = buffer;

            // --- Persistently map buffers.

            var result = vulkan.vkMapMemory(device, buffer.buffer_memory, 0, buffer_size, 0, &buffers_mapped[i]);
            if (result != vulkan.VK_SUCCESS) {
                switch (result) {
                    vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                    vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                    else => unreachable,
                }
            }
        }

        return .{
            .allocator = allocator,
            .buffers = buffers,
            .buffers_mapped = buffers_mapped,
        };
    }

    pub fn deinit(self: UniformBuffers, device: vulkan.VkDevice) void {
        var i: usize = 0;
        while (i < self.buffers.len) : (i += 1) {
            self.buffers[i].deinit(device);
        }

        self.allocator.free(self.buffers);
        self.allocator.free(self.buffers_mapped);
    }
};

pub const TextureImage = struct {
    image: VulkanImage,

    pub fn init(
        physical_device: vulkan.VkPhysicalDevice,
        device: vulkan.VkDevice,
        command_pool: vulkan.VkCommandPool,
        graphics_queue: vulkan.VkQueue,
    ) VulkanError!TextureImage {
        var tex_width: c_int = undefined;
        var tex_height: c_int = undefined;
        var tex_channels: c_int = undefined;

        const pixels: [*c]stb_image.stbi_uc = stb_image.stbi_load(
            "textures/texture.jpg",
            &tex_width,
            &tex_height,
            &tex_channels,
            stb_image.STBI_rgb_alpha,
        );
        if (pixels == null) {
            return VulkanError.image_load_failed;
        }
        defer stb_image.stbi_image_free(pixels);

        const image_size: vulkan.VkDeviceSize = @intCast(tex_width * tex_height * 4);

        // --- Staging buffer.

        var staging_buffer = try Buffer.init(
            physical_device,
            device,
            image_size,
            vulkan.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vulkan.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vulkan.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        );
        defer staging_buffer.deinit(device);

        // --- Copy data to staging buffer.

        var data: ?*anyopaque = undefined;
        var result = vulkan.vkMapMemory(device, staging_buffer.buffer_memory, 0, image_size, 0, &data);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }

        _ = c_string.memcpy(data, @ptrCast(pixels), @intCast(image_size));

        vulkan.vkUnmapMemory(device, staging_buffer.buffer_memory);

        // --- Create Vulkan image.

        var image = try VulkanImage.init(
            physical_device,
            device,
            @intCast(tex_width),
            @intCast(tex_height),
            vulkan.VK_FORMAT_R8G8B8A8_SRGB,
            vulkan.VK_IMAGE_TILING_OPTIMAL,
            vulkan.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vulkan.VK_IMAGE_USAGE_SAMPLED_BIT,
            vulkan.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        );
        errdefer image.deinit(device);

        // --- Copy data from staging buffer to image.

        try image.transition_image_layout(
            device,
            command_pool,
            graphics_queue,
            vulkan.VK_FORMAT_R8G8B8A8_SRGB,
            vulkan.VK_IMAGE_LAYOUT_UNDEFINED,
            vulkan.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        );
        try image.copy_from_buffer(
            device,
            command_pool,
            graphics_queue,
            staging_buffer,
        );

        // --- Prepare for shader access.

        try image.transition_image_layout(
            device,
            command_pool,
            graphics_queue,
            vulkan.VK_FORMAT_R8G8B8A8_SRGB,
            vulkan.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            vulkan.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        );

        // ---

        return .{
            .image = image,
        };
    }

    pub fn deinit(self: TextureImage, device: vulkan.VkDevice) void {
        self.image.deinit(device);
    }
};

const VulkanImage = struct {
    image: vulkan.VkImage,
    image_memory: vulkan.VkDeviceMemory,
    width: u32,
    height: u32,
    format: vulkan.VkFormat,
    tiling: vulkan.VkImageTiling,
    usage: vulkan.VkImageUsageFlags,
    properties: vulkan.VkMemoryPropertyFlags,

    pub fn init(
        physical_device: vulkan.VkPhysicalDevice,
        device: vulkan.VkDevice,
        width: u32,
        height: u32,
        format: vulkan.VkFormat,
        tiling: vulkan.VkImageTiling,
        usage: vulkan.VkImageUsageFlags,
        properties: vulkan.VkMemoryPropertyFlags,
    ) VulkanError!VulkanImage {
        const image_info = vulkan.VkImageCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = vulkan.VK_IMAGE_TYPE_2D,
            .extent = .{
                .width = width,
                .height = height,
                .depth = 1,
            },
            .mipLevels = 1,
            .arrayLayers = 1,
            .format = format, // must be same as pixels in buffer.
            .tiling = tiling,
            .initialLayout = vulkan.VK_IMAGE_LAYOUT_UNDEFINED,
            .usage = usage,
            .sharingMode = vulkan.VK_SHARING_MODE_EXCLUSIVE,
            .samples = vulkan.VK_SAMPLE_COUNT_1_BIT,

            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = undefined,
            .flags = 0,
        };

        var image: vulkan.VkImage = undefined;
        var result = vulkan.vkCreateImage(device, &image_info, null, &image);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }
        errdefer vulkan.vkDestroyImage(device, image, null);

        // --- Allocate and bind memory.

        var mem_requirements: vulkan.VkMemoryRequirements = undefined;
        vulkan.vkGetImageMemoryRequirements(device, image, &mem_requirements);

        const memory_type_index = try find_memory_type(physical_device, mem_requirements.memoryTypeBits, properties);
        const alloc_info = vulkan.VkMemoryAllocateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = mem_requirements.size,
            .memoryTypeIndex = memory_type_index,

            .pNext = null,
        };

        var image_memory: vulkan.VkDeviceMemory = undefined;
        result = vulkan.vkAllocateMemory(device, &alloc_info, null, &image_memory);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }
        errdefer vulkan.vkFreeMemory(device, image_memory, null);

        result = vulkan.vkBindImageMemory(device, image, image_memory, 0);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }

        // ---

        return .{
            .image = image,
            .image_memory = image_memory,
            .width = width,
            .height = height,
            .format = format,
            .tiling = tiling,
            .usage = usage,
            .properties = properties,
        };
    }

    pub fn deinit(self: VulkanImage, device: vulkan.VkDevice) void {
        vulkan.vkDestroyImage(device, self.image, null);
        vulkan.vkFreeMemory(device, self.image_memory, null);
    }

    pub fn copy_from_buffer(
        self: *VulkanImage,
        device: vulkan.VkDevice,
        command_pool: vulkan.VkCommandPool,
        graphics_queue: vulkan.VkQueue,
        buffer: Buffer,
    ) VulkanError!void {
        const command_buffer = try cbuf.begin_single_time_commands(device, command_pool);

        const region = vulkan.VkBufferImageCopy{
            .bufferOffset = 0,
            .bufferRowLength = 0,
            .bufferImageHeight = 0,
            .imageSubresource = .{
                .aspectMask = vulkan.VK_IMAGE_ASPECT_COLOR_BIT,
                .mipLevel = 0,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .imageOffset = .{
                .x = 0,
                .y = 0,
                .z = 0,
            },
            .imageExtent = .{
                .width = self.width,
                .height = self.height,
                .depth = 1,
            },
        };

        vulkan.vkCmdCopyBufferToImage(
            command_buffer,
            buffer.buffer,
            self.image,
            vulkan.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1,
            &region,
        );

        try cbuf.end_single_time_commands(device, command_pool, graphics_queue, command_buffer);
    }

    fn transition_image_layout(
        self: *VulkanImage,
        device: vulkan.VkDevice,
        command_pool: vulkan.VkCommandPool,
        graphics_queue: vulkan.VkQueue,
        format: vulkan.VkFormat,
        old_layout: vulkan.VkImageLayout,
        new_layout: vulkan.VkImageLayout,
    ) VulkanError!void {
        _ = format;
        const command_buffer = try cbuf.begin_single_time_commands(device, command_pool);

        var barrier = vulkan.VkImageMemoryBarrier{
            .sType = vulkan.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .oldLayout = old_layout,
            .newLayout = new_layout,
            .srcQueueFamilyIndex = vulkan.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = vulkan.VK_QUEUE_FAMILY_IGNORED,
            .image = self.image,
            .subresourceRange = .{
                .aspectMask = vulkan.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },

            // Set below.
            .srcAccessMask = 0,
            .dstAccessMask = 0,
        };

        // --- Transition barrier masks.

        var source_stage: vulkan.VkPipelineStageFlags = undefined;
        var destination_stage: vulkan.VkPipelineStageFlags = undefined;

        if ((old_layout == vulkan.VK_IMAGE_LAYOUT_UNDEFINED) and (new_layout == vulkan.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)) {
            barrier.srcAccessMask = 0;
            barrier.dstAccessMask = vulkan.VK_ACCESS_TRANSFER_WRITE_BIT;

            source_stage = vulkan.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
            destination_stage = vulkan.VK_PIPELINE_STAGE_TRANSFER_BIT;
        } else if (old_layout == vulkan.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL and new_layout == vulkan.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
            barrier.srcAccessMask = vulkan.VK_ACCESS_TRANSFER_WRITE_BIT;
            barrier.dstAccessMask = vulkan.VK_ACCESS_SHADER_READ_BIT;

            source_stage = vulkan.VK_PIPELINE_STAGE_TRANSFER_BIT;
            destination_stage = vulkan.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
        } else {
            return VulkanError.unsupported_layout_transition;
        }

        vulkan.vkCmdPipelineBarrier(
            command_buffer,
            source_stage,
            destination_stage,
            0,
            0,
            null,
            0,
            null,
            1,
            &barrier,
        );

        try cbuf.end_single_time_commands(device, command_pool, graphics_queue, command_buffer);
    }
};
