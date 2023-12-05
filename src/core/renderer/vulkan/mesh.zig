const std = @import("std");
const c_string = @cImport({
    @cInclude("string.h");
});
const vulkan = @import("vulkan");
const vma = @import("vma");
const buffer = @import("buffer.zig");
const Renderer = @import("../Renderer.zig");

pub fn _Mesh(comptime _VertexType: type) type {
    return struct {
        const Self = @This();
        const VertexType = _VertexType;

        vertices: std.ArrayList(VertexType),
        vertex_buffer: buffer.AllocatedBuffer,

        /// After calling this, the `vertices` field is valid and can
        /// be used but the `vertex_buffer` field is invalid. Once you
        /// have set the `vertices`, you should call the `upload` method
        /// to set the `vertex_buffer`.
        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{
                .vertices = std.ArrayList(VertexType).init(allocator),
                .vertex_buffer = undefined,
            };
        }

        pub fn deinit(self: *Self, vma_allocator: vma.VmaAllocator) void {
            self.vertices.deinit();
            self.vertex_buffer.deinit(vma_allocator);
        }

        pub fn upload(
            self: *Self,
            vma_allocator: vma.VmaAllocator,
        ) !void {
            // --- Allocate vertex buffer.

            const buffer_info = vulkan.VkBufferCreateInfo{
                .sType = vulkan.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                .size = self.vertices.items.len * @sizeOf(VertexType),
                .usage = vulkan.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            };

            const vmaallocInfo = vma.VmaAllocationCreateInfo{
                .usage = vma.VMA_MEMORY_USAGE_CPU_TO_GPU,
            };

            var res = vma.vmaCreateBuffer(
                vma_allocator,
                @ptrCast(&buffer_info),
                &vmaallocInfo,
                @ptrCast(&self.vertex_buffer.buffer),
                &self.vertex_buffer.allocation,
                null,
            );
            if (res != vulkan.VK_SUCCESS) {
                std.log.err("Failed to allocate vertex buffer", .{});
            }

            // --- Copy vertex data.

            var data: ?*anyopaque = undefined;
            res = vma.vmaMapMemory(
                vma_allocator,
                self.vertex_buffer.allocation,
                &data,
            );
            if (res != vulkan.VK_SUCCESS) {
                std.log.err("Failed to map vertex buffer", .{});
            }

            _ = c_string.memcpy(
                data,
                @ptrCast(self.vertices.items.ptr),
                @intCast(self.vertices.items.len * @sizeOf(VertexType)),
            );

            vma.vmaUnmapMemory(
                vma_allocator,
                self.vertex_buffer.allocation,
            );
        }
    };
}

pub fn MeshSystem(comptime VertexType: type) type {
    return struct {
        const Self = @This();
        pub const Mesh = _Mesh(VertexType);

        renderer: *Renderer,
        meshes: std.StringHashMap(Mesh),

        pub fn init(renderer: *Renderer) !Self {
            return .{
                .renderer = renderer,
                .meshes = std.StringHashMap(Mesh).init(renderer.allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            var it = self.meshes.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(self.renderer.system.vma_allocator);
            }
            self.meshes.deinit();
        }

        pub fn register(
            self: *Self,
            name: []const u8,
            vertices: []VertexType,
        ) !Mesh {
            var mesh = try Mesh.init(self.renderer.allocator);
            try mesh.vertices.appendSlice(vertices);

            try mesh.upload(self.renderer.system.vma_allocator);

            try self.meshes.put(name, mesh);

            return mesh;
        }

        pub fn get(
            self: *Self,
            name: []const u8,
        ) ?Mesh {
            return self.meshes.get(name);
        }
    };
}
