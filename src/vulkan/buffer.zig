const c_string = @cImport({
    @cInclude("string.h");
});
const std = @import("std");
const vulkan = @import("../c.zig").vulkan;
const VulkanError = @import("./vulkan.zig").VulkanError;
const Vertex = @import("../vertex.zig");

pub const Buffer = struct {
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

    fn copy(device: vulkan.VkDevice, command_pool: vulkan.VkCommandPool, graphics_queue: vulkan.VkQueue, src: Buffer, dest: Buffer, buffer_size: vulkan.VkDeviceSize) VulkanError!void {
        // --- Create command buffer.
        // TODO: use dedicated command pool.

        const alloc_info = vulkan.VkCommandBufferAllocateInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = command_pool,
            .level = vulkan.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,

            .pNext = null,
        };

        var command_buffer: vulkan.VkCommandBuffer = undefined;
        var result = vulkan.vkAllocateCommandBuffers(device, &alloc_info, &command_buffer);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }
        defer vulkan.vkFreeCommandBuffers(device, command_pool, 1, &command_buffer);

        // --- Record command buffer.

        const command_buffer_begin_info = vulkan.VkCommandBufferBeginInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = vulkan.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,

            .pInheritanceInfo = null,
            .pNext = null,
        };

        result = vulkan.vkBeginCommandBuffer(command_buffer, &command_buffer_begin_info);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }

        const copy_region = vulkan.VkBufferCopy{
            .srcOffset = 0,
            .dstOffset = 0,
            .size = buffer_size,
        };

        vulkan.vkCmdCopyBuffer(command_buffer, src.buffer, dest.buffer, 1, &copy_region);

        result = vulkan.vkEndCommandBuffer(command_buffer);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }

        // --- Submit command buffer.

        const submit_info = vulkan.VkSubmitInfo{
            .sType = vulkan.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount = 1,
            .pCommandBuffers = &command_buffer,

            .pNext = null,
            .waitSemaphoreCount = 0,
            .pWaitSemaphores = null,
            .pWaitDstStageMask = null,
            .signalSemaphoreCount = 0,
            .pSignalSemaphores = null,
        };

        result = vulkan.vkQueueSubmit(graphics_queue, 1, &submit_info, null);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }

        result = vulkan.vkQueueWaitIdle(graphics_queue);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }
    }

    fn find_memory_type(physical_device: vulkan.VkPhysicalDevice, memory_type_filter: u32, properties: vulkan.VkMemoryPropertyFlags) VulkanError!u32 {
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
