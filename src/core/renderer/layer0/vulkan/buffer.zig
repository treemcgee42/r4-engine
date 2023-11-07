pub const vulkan = @import("vulkan");
pub const l0vk = @import("./vulkan.zig");

// ---

pub const VkMemoryPropertyFlags = packed struct(u32) {
    device_local_bit: bool = false,
    host_visible_bit: bool = false,
    host_coherent_bit: bool = false,
    host_cached_bit: bool = false,

    lazily_allocated_bit: bool = false,
    protected_bit: bool = false,
    device_coherent_bit_amd: bool = false,
    device_uncached_bit_amd: bool = false,

    rdma_capable_bit_nv: bool = false,
    _: u23 = 0,

    pub const Bits = enum(c_uint) {
        device_local = 0x00000001,
        host_visible = 0x00000002,
        host_coherent = 0x00000004,
        host_cached = 0x00000008,

        lazily_allocated = 0x00000010,
        protected = 0x00000020,
        device_coherent_amd = 0x00000040,
        device_uncached_amd = 0x00000080,

        rdma_capable_nv = 0x00000100,
    };
};

pub const VkMemoryType = struct {
    propertyFlags: VkMemoryPropertyFlags,
    heapIndex: u32,

    pub fn from_vulkan_ty(ty: vulkan.VkMemoryType) VkMemoryType {
        return .{
            .propertyFlags = @bitCast(ty.propertyFlags),
            .heapIndex = ty.heapIndex,
        };
    }
};

pub const VkMemoryHeapFlags = packed struct(u32) {
    device_local_bit: bool = false,
    multi_instance_bit: bool = false,
    _: u30 = 0,

    pub const Bits = enum(c_uint) {
        device_local = 0x00000001,
        multi_instance = 0x00000002,
    };
};

pub const VkMemoryHeap = struct {
    size: l0vk.VkDeviceSize,
    flags: VkMemoryHeapFlags,

    pub fn from_vulkan_ty(ty: vulkan.VkMemoryHeap) VkMemoryHeap {
        return .{
            .size = ty.size,
            .flags = @bitCast(ty.flags),
        };
    }
};

pub const MAX_MEMORY_TYPES = vulkan.VK_MAX_MEMORY_TYPES;
pub const MAX_MEMORY_HEAPS = vulkan.VK_MAX_MEMORY_HEAPS;

pub const VkPhysicalDeviceMemoryProperties = struct {
    memory_types: []VkMemoryType,
    memory_heaps: []VkMemoryHeap,

    _mem_type_buffer: [MAX_MEMORY_TYPES]VkMemoryType,
    _mem_heap_buffer: [MAX_MEMORY_HEAPS]VkMemoryHeap,

    pub fn from_vulkan_ty(ty: vulkan.VkPhysicalDeviceMemoryProperties) VkPhysicalDeviceMemoryProperties {
        var mem_type_buffer: [MAX_MEMORY_TYPES]VkMemoryType = undefined;
        var mem_heap_buffer: [MAX_MEMORY_HEAPS]VkMemoryHeap = undefined;

        var i: usize = 0;
        while (i < ty.memoryTypeCount) : (i += 1) {
            mem_type_buffer[i] = VkMemoryType.from_vulkan_ty(ty.memoryTypes[i]);
        }
        i = 0;
        while (i < ty.memoryHeapCount) : (i += 1) {
            mem_heap_buffer[i] = VkMemoryHeap.from_vulkan_ty(ty.memoryHeaps[i]);
        }

        return .{
            ._mem_type_buffer = mem_type_buffer,
            ._mem_heap_buffer = mem_heap_buffer,

            .memory_types = mem_type_buffer[0..ty.memoryTypeCount],
            .memory_heaps = mem_heap_buffer[0..ty.memoryHeapCount],
        };
    }
};

pub fn vkGetPhysicalDeviceMemoryProperties(physicalDevice: l0vk.VkPhysicalDevice) VkPhysicalDeviceMemoryProperties {
    var memory_properties: vulkan.VkPhysicalDeviceMemoryProperties = undefined;
    vulkan.vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memory_properties);

    return VkPhysicalDeviceMemoryProperties.from_vulkan_ty(memory_properties);
}
