const c_string = @cImport({
    @cInclude("string.h");
});
const stb_image = @import("../../../c.zig").stb_image;
const std = @import("std");
const vulkan = @import("vulkan");
const VulkanError = @import("./VulkanSystem.zig").VulkanError;
const cbuf = @import("../../../vulkan/command_buffer.zig");
const vertex = @import("../../../vertex.zig");
const l0vk = @import("../layer0/vulkan/vulkan.zig");

fn find_memory_type(
    physical_device: l0vk.VkPhysicalDevice,
    memory_type_filter: u32,
    properties: l0vk.VkMemoryPropertyFlags,
) !u32 {
    const memory_properties = l0vk.vkGetPhysicalDeviceMemoryProperties(physical_device);

    var i: u5 = 0;
    while (i < memory_properties.memory_types.len) : (i += 1) {
        const suitable_type = (memory_type_filter & (@as(u32, @intCast(1)) << i) > 0);
        const suitable_properties = @as(u32, @bitCast(l0vk.and_op_flags(
            memory_properties.memory_types[i].propertyFlags,
            properties,
        ))) == @as(u32, @bitCast(properties));

        if (suitable_type and suitable_properties) {
            return i;
        }
    }

    return VulkanError.no_suitable_memory_type;
}

fn find_supported_format(
    physical_device: vulkan.VkPhysicalDevice,
    candidates: []const vulkan.VkFormat,
    tiling: vulkan.VkImageTiling,
    features: vulkan.VkFormatFeatureFlags,
) VulkanError!vulkan.VkFormat {
    var i: usize = 0;
    while (i < candidates.len) : (i += 1) {
        const format: vulkan.VkFormat = candidates[i];

        var properties: vulkan.VkFormatProperties = undefined;
        vulkan.vkGetPhysicalDeviceFormatProperties(physical_device, format, &properties);

        if ((tiling == vulkan.VK_IMAGE_TILING_LINEAR) and
            ((properties.linearTilingFeatures & features) == features))
        {
            return format;
        } else if ((tiling == vulkan.VK_IMAGE_TILING_OPTIMAL) and
            ((properties.optimalTilingFeatures & features) == features))
        {
            return format;
        }
    }

    return VulkanError.no_supported_format;
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
        vertices: []vertex.Vertex,
    ) VulkanError!VertexBuffer {
        const buffer_size = @sizeOf(vertex.Vertex) * vertices.len;

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

        _ = c_string.memcpy(data, @ptrCast(vertices[0..].ptr), @intCast(buffer_size));

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
        indices: []u32,
    ) VulkanError!IndexBuffer {
        const buffer_size = @sizeOf(@TypeOf(indices[0])) * indices.len;

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

        _ = c_string.memcpy(data, @ptrCast(indices[0..].ptr), @intCast(buffer_size));

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
            .len = indices.len,
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

        const buffer_size = @sizeOf(vertex.UniformBufferObject);

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
    image_view: vulkan.VkImageView,
    sampler: vulkan.VkSampler,

    pub fn init(
        physical_device: vulkan.VkPhysicalDevice,
        device: vulkan.VkDevice,
        command_pool: vulkan.VkCommandPool,
        graphics_queue: vulkan.VkQueue,
        texture_path: [*c]const u8,
    ) VulkanError!TextureImage {
        var image = try create_texture_image(
            physical_device,
            device,
            command_pool,
            graphics_queue,
            texture_path,
        );

        const image_view = try create_texture_image_view(device, &image);

        const sampler = try create_texture_sampler(physical_device, device, image);

        return .{
            .image = image,
            .image_view = image_view,
            .sampler = sampler,
        };
    }

    fn create_texture_image(
        physical_device: vulkan.VkPhysicalDevice,
        device: vulkan.VkDevice,
        command_pool: vulkan.VkCommandPool,
        graphics_queue: vulkan.VkQueue,
        texture_path: [*c]const u8,
    ) VulkanError!VulkanImage {
        var tex_width: c_int = undefined;
        var tex_height: c_int = undefined;
        var tex_channels: c_int = undefined;

        const pixels: [*c]stb_image.stbi_uc = stb_image.stbi_load(
            texture_path,
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

        const mip_levels: u32 = std.math.log2_int(u32, @as(u32, @intCast(@max(tex_width, tex_height)))) + 1;

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
            mip_levels,
            vulkan.VK_SAMPLE_COUNT_1_BIT,
            vulkan.VK_FORMAT_R8G8B8A8_SRGB,
            vulkan.VK_IMAGE_TILING_OPTIMAL,
            vulkan.VK_IMAGE_USAGE_TRANSFER_SRC_BIT | vulkan.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vulkan.VK_IMAGE_USAGE_SAMPLED_BIT,
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

        // --- Generate mipmaps.
        // Also transitions to VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL.

        try image.generate_mipmaps(physical_device, device, command_pool, graphics_queue);

        // ---

        return image;
    }

    fn create_texture_image_view(device: vulkan.VkDevice, texture_image: *VulkanImage) VulkanError!vulkan.VkImageView {
        const image_view = try texture_image.create_image_view(device, vulkan.VK_IMAGE_ASPECT_COLOR_BIT);

        return image_view;
    }

    fn create_texture_sampler(
        physical_device: vulkan.VkPhysicalDevice,
        device: vulkan.VkDevice,
        image: VulkanImage,
    ) VulkanError!vulkan.VkSampler {
        var properties: vulkan.VkPhysicalDeviceProperties = undefined;
        vulkan.vkGetPhysicalDeviceProperties(physical_device, &properties);

        const sampler_info = vulkan.VkSamplerCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .magFilter = vulkan.VK_FILTER_LINEAR,
            .minFilter = vulkan.VK_FILTER_LINEAR,
            .addressModeU = vulkan.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .addressModeV = vulkan.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .addressModeW = vulkan.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .anisotropyEnable = vulkan.VK_TRUE,
            .maxAnisotropy = properties.limits.maxSamplerAnisotropy,
            .borderColor = vulkan.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
            .unnormalizedCoordinates = vulkan.VK_FALSE,
            .compareEnable = vulkan.VK_FALSE,
            .compareOp = vulkan.VK_COMPARE_OP_ALWAYS,
            .mipmapMode = vulkan.VK_SAMPLER_MIPMAP_MODE_LINEAR,
            .mipLodBias = 0.0,
            .minLod = 0.0,
            .maxLod = @floatFromInt(image.mip_levels),
        };

        var sampler: vulkan.VkSampler = undefined;
        var result = vulkan.vkCreateSampler(device, &sampler_info, null, &sampler);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }

        return sampler;
    }

    pub fn deinit(self: TextureImage, device: vulkan.VkDevice) void {
        vulkan.vkDestroySampler(device, self.sampler, null);
        vulkan.vkDestroyImageView(device, self.image_view, null);
        self.image.deinit(device);
    }
};

pub const DepthImage = struct {
    image: VulkanImage,
    image_view: vulkan.VkImageView,

    pub fn init(
        physical_device: vulkan.VkPhysicalDevice,
        device: vulkan.VkDevice,
        width: u32,
        height: u32,
        num_samples: u32,
    ) VulkanError!DepthImage {
        const depth_format = try find_depth_format(physical_device);

        var depth_image = try VulkanImage.init(
            physical_device,
            device,
            width,
            height,
            1,
            num_samples,
            depth_format,
            vulkan.VK_IMAGE_TILING_OPTIMAL,
            vulkan.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
            .{ .device_local_bit = true },
            // vulkan.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        );
        errdefer depth_image.deinit(device);

        const depth_image_view = try depth_image.create_image_view(device, vulkan.VK_IMAGE_ASPECT_DEPTH_BIT);

        return .{
            .image = depth_image,
            .image_view = depth_image_view,
        };
    }

    pub fn deinit(self: DepthImage, device: vulkan.VkDevice) void {
        vulkan.vkDestroyImageView(device, self.image_view, null);
        self.image.deinit(device);
    }

    pub fn find_depth_format(physical_device: vulkan.VkPhysicalDevice) VulkanError!vulkan.VkFormat {
        const to_return = try find_supported_format(
            physical_device,
            &[_]vulkan.VkFormat{
                vulkan.VK_FORMAT_D32_SFLOAT,
                vulkan.VK_FORMAT_D32_SFLOAT_S8_UINT,
                vulkan.VK_FORMAT_D24_UNORM_S8_UINT,
            },
            vulkan.VK_IMAGE_TILING_OPTIMAL,
            vulkan.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT,
        );

        return to_return;
    }

    fn has_stencil_component(format: vulkan.VkFormat) bool {
        return format == vulkan.VK_FORMAT_D32_SFLOAT_S8_UINT or format == vulkan.VK_FORMAT_D24_UNORM_S8_UINT;
    }
};

pub const ColorImage = struct {
    image: VulkanImage,
    image_view: vulkan.VkImageView,

    pub fn init(
        physical_device: vulkan.VkPhysicalDevice,
        device: vulkan.VkDevice,
        width: u32,
        height: u32,
        format: vulkan.VkFormat,
        num_samples: vulkan.VkSampleCountFlagBits,
        // vulkan.VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT | vulkan.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        usage: vulkan.VkImageUsageFlags,
    ) VulkanError!ColorImage {
        var image = try VulkanImage.init(
            physical_device,
            device,
            width,
            height,
            1,
            num_samples,
            format,
            vulkan.VK_IMAGE_TILING_OPTIMAL,
            usage,
            .{ .device_local_bit = true },
        );
        errdefer image.deinit(device);

        const image_view = try image.create_image_view(device, vulkan.VK_IMAGE_ASPECT_COLOR_BIT);

        return .{
            .image = image,
            .image_view = image_view,
        };
    }

    pub fn deinit(self: ColorImage, device: vulkan.VkDevice) void {
        vulkan.vkDestroyImageView(device, self.image_view, null);
        self.image.deinit(device);
    }

    pub fn find_depth_format(physical_device: vulkan.VkPhysicalDevice) VulkanError!vulkan.VkFormat {
        const to_return = try find_supported_format(
            physical_device,
            &[_]vulkan.VkFormat{
                vulkan.VK_FORMAT_D32_SFLOAT,
                vulkan.VK_FORMAT_D32_SFLOAT_S8_UINT,
                vulkan.VK_FORMAT_D24_UNORM_S8_UINT,
            },
            vulkan.VK_IMAGE_TILING_OPTIMAL,
            vulkan.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT,
        );

        return to_return;
    }

    fn has_stencil_component(format: vulkan.VkFormat) bool {
        return format == vulkan.VK_FORMAT_D32_SFLOAT_S8_UINT or format == vulkan.VK_FORMAT_D24_UNORM_S8_UINT;
    }
};

const VulkanImage = struct {
    image: vulkan.VkImage,
    image_memory: vulkan.VkDeviceMemory,
    width: u32,
    height: u32,
    mip_levels: u32,
    format: vulkan.VkFormat,
    tiling: vulkan.VkImageTiling,
    usage: vulkan.VkImageUsageFlags,
    properties: l0vk.VkMemoryPropertyFlags,

    pub fn init(
        physical_device: vulkan.VkPhysicalDevice,
        device: vulkan.VkDevice,
        width: u32,
        height: u32,
        mip_levels: u32,
        num_samples: vulkan.VkSampleCountFlagBits,
        format: vulkan.VkFormat,
        tiling: vulkan.VkImageTiling,
        usage: vulkan.VkImageUsageFlags,
        properties: l0vk.VkMemoryPropertyFlags,
    ) VulkanError!VulkanImage {
        const image_info = vulkan.VkImageCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = vulkan.VK_IMAGE_TYPE_2D,
            .extent = .{
                .width = width,
                .height = height,
                .depth = 1,
            },
            .mipLevels = mip_levels,
            .arrayLayers = 1,
            .format = format, // must be same as pixels in buffer.
            .tiling = tiling,
            .initialLayout = vulkan.VK_IMAGE_LAYOUT_UNDEFINED,
            .usage = usage,
            .sharingMode = vulkan.VK_SHARING_MODE_EXCLUSIVE,
            .samples = num_samples,

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
            .mip_levels = mip_levels,
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

    pub fn create_image_view(
        self: *VulkanImage,
        device: vulkan.VkDevice,
        aspect_flags: vulkan.VkImageAspectFlags,
    ) VulkanError!vulkan.VkImageView {
        const view_info = vulkan.VkImageViewCreateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = self.image,
            .viewType = vulkan.VK_IMAGE_VIEW_TYPE_2D,
            .format = self.format,
            .subresourceRange = vulkan.VkImageSubresourceRange{
                .aspectMask = aspect_flags,
                .baseMipLevel = 0,
                .levelCount = self.mip_levels,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },

            .components = .{
                .r = vulkan.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = vulkan.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = vulkan.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = vulkan.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .pNext = null,
            .flags = 0,
        };

        var image_view: vulkan.VkImageView = undefined;
        var result = vulkan.vkCreateImageView(device, &view_info, null, &image_view);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }

        return image_view;
    }

    pub fn generate_mipmaps(
        self: *VulkanImage,
        physical_device: vulkan.VkPhysicalDevice,
        device: vulkan.VkDevice,
        command_pool: vulkan.VkCommandPool,
        graphics_queue: vulkan.VkQueue,
    ) VulkanError!void {
        // --- Check if image format supports linear blitting.

        var format_properties: vulkan.VkFormatProperties = undefined;
        vulkan.vkGetPhysicalDeviceFormatProperties(physical_device, self.format, &format_properties);
        if (format_properties.optimalTilingFeatures & vulkan.VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT == 0) {
            return VulkanError.no_supported_format;
        }

        // ---

        var command_buffer = try cbuf.begin_single_time_commands(device, command_pool);

        var barrier = vulkan.VkImageMemoryBarrier{ .sType = vulkan.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .image = self.image, .srcQueueFamilyIndex = vulkan.VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = vulkan.VK_QUEUE_FAMILY_IGNORED, .subresourceRange = .{
            .aspectMask = vulkan.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseArrayLayer = 0,
            .layerCount = 1,
            .levelCount = 1,
        } };

        var mip_width: i32 = @intCast(self.width);
        var mip_height: i32 = @intCast(self.height);

        var i: usize = 1;
        while (i < self.mip_levels) : (i += 1) {
            barrier.subresourceRange.baseMipLevel = @intCast(i - 1);
            barrier.oldLayout = vulkan.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
            barrier.newLayout = vulkan.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
            barrier.srcAccessMask = vulkan.VK_ACCESS_TRANSFER_WRITE_BIT;
            barrier.dstAccessMask = vulkan.VK_ACCESS_TRANSFER_READ_BIT;

            vulkan.vkCmdPipelineBarrier(command_buffer, vulkan.VK_PIPELINE_STAGE_TRANSFER_BIT, vulkan.VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, &barrier);

            var dst_offset_x: i32 = 1;
            if (mip_width > 1) {
                dst_offset_x = @divFloor(mip_width, 2);
            }
            var dst_offset_y: i32 = 1;
            if (mip_height > 1) {
                dst_offset_y = @divFloor(mip_height, 2);
            }
            const blit = vulkan.VkImageBlit{
                .srcOffsets = [_]vulkan.VkOffset3D{
                    .{
                        .x = 0,
                        .y = 0,
                        .z = 0,
                    },
                    .{
                        .x = mip_width,
                        .y = mip_height,
                        .z = 1,
                    },
                },
                .srcSubresource = .{
                    .aspectMask = vulkan.VK_IMAGE_ASPECT_COLOR_BIT,
                    .mipLevel = @intCast(i - 1),
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
                .dstOffsets = [_]vulkan.VkOffset3D{
                    .{
                        .x = 0,
                        .y = 0,
                        .z = 0,
                    },
                    .{
                        .x = dst_offset_x,
                        .y = dst_offset_y,
                        .z = 1,
                    },
                },
                .dstSubresource = .{
                    .aspectMask = vulkan.VK_IMAGE_ASPECT_COLOR_BIT,
                    .mipLevel = @intCast(i),
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };

            vulkan.vkCmdBlitImage(
                command_buffer,
                self.image,
                vulkan.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                self.image,
                vulkan.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                1,
                &blit,
                vulkan.VK_FILTER_LINEAR,
            );

            barrier.oldLayout = vulkan.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
            barrier.newLayout = vulkan.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
            barrier.srcAccessMask = vulkan.VK_ACCESS_TRANSFER_READ_BIT;
            barrier.dstAccessMask = vulkan.VK_ACCESS_SHADER_READ_BIT;

            vulkan.vkCmdPipelineBarrier(
                command_buffer,
                vulkan.VK_PIPELINE_STAGE_TRANSFER_BIT,
                vulkan.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                0,
                0,
                null,
                0,
                null,
                1,
                &barrier,
            );

            if (mip_width > 1) {
                mip_width = @divFloor(mip_width, 2);
            }
            if (mip_height > 1) {
                mip_height = @divFloor(mip_height, 2);
            }
        }

        barrier.subresourceRange.baseMipLevel = self.mip_levels - 1;
        barrier.oldLayout = vulkan.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.newLayout = vulkan.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        barrier.srcAccessMask = vulkan.VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = vulkan.VK_ACCESS_SHADER_READ_BIT;

        vulkan.vkCmdPipelineBarrier(
            command_buffer,
            vulkan.VK_PIPELINE_STAGE_TRANSFER_BIT,
            vulkan.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
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

    // void generateMipmaps(VkImage image, int32_t texWidth, int32_t texHeight, uint32_t mipLevels) {
    //     VkCommandBuffer commandBuffer = beginSingleTimeCommands();
    //
    //     VkImageMemoryBarrier barrier{};
    //     barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    //     barrier.image = image;
    //     barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    //     barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    //     barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    //     barrier.subresourceRange.baseArrayLayer = 0;
    //     barrier.subresourceRange.layerCount = 1;
    //     barrier.subresourceRange.levelCount = 1;
    //
    //     endSingleTimeCommands(commandBuffer);
    // }

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
                .levelCount = self.mip_levels,
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
