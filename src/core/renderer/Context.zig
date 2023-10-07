const std = @import("std");
const VulkanSystem = @import("./vulkan//VulkanSystem.zig");

backend: Backend,
system: union {
    vulkan: VulkanSystem,
},

pub const Backend = enum {
    vulkan,
};

const Context = @This();

pub fn init(allocator: std.mem.Allocator, backend: Backend) !Context {
    const system = switch (backend) {
        .vulkan => try VulkanSystem.init(allocator),
    };

    return .{
        .backend = backend,
        .system = .{ .vulkan = system },
    };
}
