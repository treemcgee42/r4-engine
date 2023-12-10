const std = @import("std");
const cgltf = @import("cgltf");
// In the future this could probably be generic.
const Vertex = @import("../Scene.zig").Vertex;
const Mesh = @import("../Scene.zig").Mesh;

// We assume the allocator is a `std.mem.Allocator`.
fn zig_alloc_fn(user: ?*anyopaque, size: cgltf.cgltf_size) callconv(.C) ?*anyopaque {
    var allocator: *std.mem.Allocator = @ptrCast(@alignCast(user.?));

    // Allocate an extra item so we can store the size at the beginning of the slice.
    var slice = allocator.alloc(u8, size + @sizeOf(cgltf.cgltf_size)) catch unreachable;

    var size_bytes: *cgltf.cgltf_size = @ptrCast(@alignCast(slice[0..@sizeOf(cgltf.cgltf_size)]));
    size_bytes.* = size;

    return @ptrCast(slice.ptr + @sizeOf(cgltf.cgltf_size));
}

fn zig_free_fn(user: ?*anyopaque, ptr: ?*anyopaque) callconv(.C) void {
    if (ptr == null) return;

    var allocator: *std.mem.Allocator = @ptrCast(@alignCast(user.?));

    var ptr_to_original_first_element: [*]u8 = @as([*]u8, @ptrCast(@alignCast(ptr.?))) - @sizeOf(cgltf.cgltf_size);
    const size_bytes: *cgltf.cgltf_size = @ptrCast(@alignCast(ptr_to_original_first_element[0..@sizeOf(cgltf.cgltf_size)]));
    const size = size_bytes.*;
    var slice = ptr_to_original_first_element[0 .. size + @sizeOf(cgltf.cgltf_size)];

    allocator.free(slice);
}

pub const CgltfError = error{
    result_data_too_short,
    result_unknown_format,
    result_invalid_json,
    result_invalid_gltf,
    result_invalid_options,
    result_file_not_found,
    result_io_error,
    result_out_of_memory,
    result_legacy_gltf,
};

fn handle_cgltf_result(result: cgltf.cgltf_result) CgltfError!void {
    switch (result) {
        cgltf.cgltf_result_success => {},
        cgltf.cgltf_result_data_too_short => {
            return CgltfError.result_data_too_short;
        },
        cgltf.cgltf_result_unknown_format => {
            return CgltfError.result_unknown_format;
        },
        cgltf.cgltf_result_invalid_json => {
            return CgltfError.result_invalid_json;
        },
        cgltf.cgltf_result_invalid_gltf => {
            return CgltfError.result_invalid_gltf;
        },
        cgltf.cgltf_result_invalid_options => {
            return CgltfError.result_invalid_options;
        },
        cgltf.cgltf_result_file_not_found => {
            return CgltfError.result_file_not_found;
        },
        cgltf.cgltf_result_io_error => {
            return CgltfError.result_io_error;
        },
        cgltf.cgltf_result_out_of_memory => {
            return CgltfError.result_out_of_memory;
        },
        cgltf.cgltf_result_legacy_gltf => {
            return CgltfError.result_legacy_gltf;
        },
        else => {
            unreachable;
        },
    }
}

pub fn load_from_file(allocator: *std.mem.Allocator, path_to_gltf_file: [*c]const u8) CgltfError!void {
    const cgltf_memory_options = cgltf.cgltf_memory_options{
        .alloc_func = &zig_alloc_fn,
        .free_func = &zig_free_fn,
        .user_data = @ptrCast(allocator),
    };

    const cgltf_options = cgltf.cgltf_options{
        .type = undefined, // auto detect
        .json_token_count = 0, // auto
        .memory = cgltf_memory_options,
        .file = std.mem.zeroInit(cgltf.cgltf_file_options, .{}), // Could make Zig-based, this just does C defaults.
    };

    var out_data: [*c]cgltf.cgltf_data = null;
    const result = cgltf.cgltf_parse_file(&cgltf_options, path_to_gltf_file, &out_data);
    try handle_cgltf_result(result);

    cgltf.cgltf_free(out_data);
}
