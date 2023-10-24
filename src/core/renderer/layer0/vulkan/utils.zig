const std = @import("std");
const vulkan = @import("vulkan");

pub fn derived_from_vulkan_ty(vulkan_ty_instance: anytype, comptime TargetType: type) TargetType {
    var to_return: TargetType = undefined;

    inline for (std.meta.fields(@TypeOf(vulkan_ty_instance))) |field| {
        if (field.type == u32 or
            field.type == i32 or
            field.type == f32 or
            field.type == usize or
            field.type == [2]u32 or
            field.type == [3]u32 or
            field.type == [2]f32 or
            field.type == [16]u8 or
            field.type == [256]u8 or
            field.type == vulkan.VkDeviceSize)
        {
            const TargetFieldType = @TypeOf(@field(to_return, field.name));
            if (TargetFieldType == bool) {
                @field(to_return, field.name) = @field(vulkan_ty_instance, field.name) != 0;
                continue;
            }

            @field(to_return, field.name) = @bitCast(@field(vulkan_ty_instance, field.name));
            continue;
        }

        const TargetFieldType = @TypeOf(@field(to_return, field.name));
        @field(to_return, field.name) = TargetFieldType.from_vulkan_ty(@field(vulkan_ty_instance, field.name));
    }

    return to_return;
}

pub fn derived_to_vulkan_ty(wrapper_ty_instance: anytype, comptime TargetType: type) TargetType {
    var to_return: TargetType = undefined;

    inline for (std.meta.fields(@TypeOf(wrapper_ty_instance))) |field| {
        switch (field.type) {
            bool => {
                @field(to_return, field.name) = @intFromBool(@field(wrapper_ty_instance, field.name));
            },
            else => unreachable,
        }
    }

    return to_return;
}
