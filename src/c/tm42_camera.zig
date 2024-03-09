pub usingnamespace @cImport({
    @cDefine("TM42_MATH_IMPLEMENTATION", "");
    @cDefine("TM42_CAMERA_IMPLEMENTATION", "");
    @cInclude("tm42_turntable_camera.h");
});

const std = @import("std");

pub var allocator: ?std.mem.Allocator = null;

pub fn zigAllocator(bytes: usize) callconv(.C) ?*anyopaque {
    return @ptrCast(allocator.?.alloc(u8, bytes) catch return null);
}
