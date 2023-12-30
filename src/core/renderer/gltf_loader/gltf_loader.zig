const std = @import("std");
const du = @import("debug_utils");
const cgltf = @import("cgltf");
const math = @import("../../../math.zig");
// In the future this could probably be generic.
const Vertex = @import("../Scene.zig").Vertex;
const Mesh = @import("../Scene.zig").Mesh;

// We assume the allocator is a `std.mem.Allocator`.
fn zig_alloc_fn(user: ?*anyopaque, size: cgltf.cgltf_size) callconv(.C) ?*anyopaque {
    var allocator: *std.mem.Allocator = @ptrCast(@alignCast(user.?));

    // Allocate an extra item so we can store the size at the beginning of the slice.
    var slice = allocator.alloc(u8, size + @sizeOf(cgltf.cgltf_size)) catch unreachable;

    const size_bytes: *cgltf.cgltf_size = @ptrCast(@alignCast(slice[0..@sizeOf(cgltf.cgltf_size)]));
    size_bytes.* = size;

    return @ptrCast(slice.ptr + @sizeOf(cgltf.cgltf_size));
}

fn zig_free_fn(user: ?*anyopaque, ptr: ?*anyopaque) callconv(.C) void {
    if (ptr == null) return;

    var allocator: *std.mem.Allocator = @ptrCast(@alignCast(user.?));

    var ptr_to_original_first_element: [*]u8 = @as([*]u8, @ptrCast(@alignCast(ptr.?))) - @sizeOf(cgltf.cgltf_size);
    const size_bytes: *cgltf.cgltf_size = @ptrCast(@alignCast(ptr_to_original_first_element[0..@sizeOf(cgltf.cgltf_size)]));
    const size = size_bytes.*;
    const slice = ptr_to_original_first_element[0 .. size + @sizeOf(cgltf.cgltf_size)];

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
            std.log.err("cgltf error: invalid json", .{});
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

fn calculate_num_triangles_to_draw(
    num_verts: usize,
    topology_type: cgltf.cgltf_primitive_type,
) usize {
    return switch (topology_type) {
        cgltf.cgltf_primitive_type_triangles => num_verts / 3,
        else => {
            @panic("not implemented");
        },
    };
}

inline fn print_indentation(indentation_level: u8) void {
    var i: u8 = 0;
    while (i < indentation_level) : (i += 1) {
        std.debug.print("  ", .{});
    }
}

inline fn print_newline_and_indentation(indentation_level: u8) void {
    std.debug.print("\n", .{});
    print_indentation(indentation_level);
}

pub fn debug_print_gltf_data(gltf_data: *cgltf.cgltf_data) void {
    var indentation_level: u8 = 0;
    var i: usize = 0;
    var j: usize = 0;
    var k: usize = 0;

    std.debug.print("{{", .{});

    indentation_level += 1;

    // MESHES
    print_newline_and_indentation(indentation_level);
    std.debug.print("meshes ({d}): {{", .{gltf_data.meshes_count});
    indentation_level += 1;
    i = 0;
    while (i < gltf_data.meshes_count) : (i += 1) {
        // NAME
        print_newline_and_indentation(indentation_level);
        if (gltf_data.meshes[i].name != null) {
            std.debug.print("name: \"{s}\",", .{gltf_data.meshes[i].name});
        } else {
            std.debug.print("name: n/a", .{});
        }

        // PRIMITIVES
        print_newline_and_indentation(indentation_level);
        std.debug.print("primitives ({d}): {{", .{gltf_data.meshes[i].primitives_count});
        indentation_level += 1;
        j = 0;
        while (j < gltf_data.meshes[i].primitives_count) : (j += 1) {
            const primitive = gltf_data.meshes[i].primitives[j];

            print_newline_and_indentation(indentation_level);
            std.debug.print("{{", .{});

            indentation_level += 1;

            // Start

            // TYPE
            const type_ = switch (primitive.type) {
                cgltf.cgltf_primitive_type_invalid => "invalid",
                cgltf.cgltf_primitive_type_points => "points",
                cgltf.cgltf_primitive_type_lines => "lines",
                cgltf.cgltf_primitive_type_line_loop => "line_loop",
                cgltf.cgltf_primitive_type_line_strip => "line_strip",
                cgltf.cgltf_primitive_type_triangles => "triangles",
                cgltf.cgltf_primitive_type_triangle_strip => "triangle_strip",
                cgltf.cgltf_primitive_type_triangle_fan => "triangle_fan",
                cgltf.cgltf_primitive_type_max_enum => "max_enum",
                else => {
                    du.log(
                        "gltf loader",
                        .err,
                        "unknown primitive type, enum value {d} - this mesh will be skipped",
                        .{primitive.type},
                    );
                    continue;
                },
            };
            print_newline_and_indentation(indentation_level);
            std.debug.print("type: {s},", .{type_});

            // ATTRIBUTES
            print_newline_and_indentation(indentation_level);
            std.debug.print("attributes (index into accessor array): {{", .{});
            indentation_level += 1;
            k = 0;
            while (k < primitive.attributes_count) : (k += 1) {
                const attribute = primitive.attributes[k];

                print_newline_and_indentation(indentation_level);
                std.debug.print("{s}: {{,", .{attribute.name});

                // ---

                indentation_level += 1;

                print_newline_and_indentation(indentation_level);
                std.debug.print("index: {d},", .{attribute.index});
                const attr_type = switch (attribute.type) {
                    cgltf.cgltf_attribute_type_invalid => "invalid",
                    cgltf.cgltf_attribute_type_position => "position",
                    cgltf.cgltf_attribute_type_normal => "normal",
                    else => {
                        du.log(
                            "gltf loader",
                            .err,
                            "unknown attribute type, enum value {d} - this attribute will be skipped",
                            .{attribute.type},
                        );
                        continue;
                    },
                };
                print_newline_and_indentation(indentation_level);
                std.debug.print("type: {s},", .{attr_type});
                print_newline_and_indentation(indentation_level);
                std.debug.print("accessor_count: {d},", .{attribute.data.*.count});

                indentation_level -= 1;

                print_newline_and_indentation(indentation_level);
                std.debug.print("}},", .{});

                // ---
            }
            indentation_level -= 1;
            print_newline_and_indentation(indentation_level);
            std.debug.print("}},", .{});

            // INDICES
            print_newline_and_indentation(indentation_level);
            std.debug.print("indices (count): ", .{});
            var num_verts = gltf_data.accessors[@intCast(primitive.attributes[0].index)].count;
            if (primitive.indices != null) {
                num_verts = primitive.indices.*.count;
                std.debug.print("{d} ", .{num_verts});
            } else {
                std.debug.print("n/a ", .{});
            }
            const num_tris = calculate_num_triangles_to_draw(num_verts, primitive.type);
            std.debug.print("({d} triangles to draw)", .{num_tris});

            // End

            indentation_level -= 1;

            print_newline_and_indentation(indentation_level);
            std.debug.print("}},", .{});
        }
        indentation_level -= 1;

        print_newline_and_indentation(indentation_level);
        std.debug.print("}},", .{});
    }
    indentation_level -= 1;

    print_newline_and_indentation(indentation_level);
    std.debug.print("}},", .{});

    std.debug.print("\n}}\n", .{});
}

fn parse_primitive_verts_type_triangles(
    allocator: *std.mem.Allocator,
    gltf_data: *cgltf.cgltf_data,
    primitive: cgltf.cgltf_primitive,
) ![]Vertex {
    _ = gltf_data;
    var i: usize = 0;

    var indices_accessor: ?*cgltf.cgltf_accessor = null;
    if (primitive.indices != null) {
        indices_accessor = primitive.indices;
    }

    var position_accessor: ?*cgltf.cgltf_accessor = null;
    i = 0;
    while (i < primitive.attributes_count) : (i += 1) {
        const attribute = primitive.attributes[i];
        switch (attribute.type) {
            cgltf.cgltf_attribute_type_position => {
                position_accessor = attribute.data; // &gltf_data.accessors[@intCast(attribute.index)];
            },
            else => {
                du.log(
                    "renderer",
                    .warn,
                    "in function {s}: GLTF data includes attribute type '{s}' but the parser doesn't know how to parse it, so it will be ignored",
                    .{ @src().fn_name, attribute.name },
                );
            },
        }
    }

    du.production_assert(position_accessor != null);
    du.production_assert(indices_accessor != null);

    var vertices = try allocator.alloc(Vertex, indices_accessor.?.count);
    errdefer allocator.free(vertices);

    if (indices_accessor != null) {
        i = 0;
        while (i < indices_accessor.?.count) : (i += 1) {
            const idx_0 = cgltf.cgltf_accessor_read_index(indices_accessor, i);
            // std.debug.print("{d}: ", .{index});

            var pos: [3]cgltf.cgltf_float = [_]cgltf.cgltf_float{ -69.0, -69.0, -69.0 };
            const res = cgltf.cgltf_accessor_read_float(
                position_accessor,
                idx_0,
                &pos,
                3,
            );
            if (res == 0) {
                std.log.err("{s}\tfailed to read position\n", .{@src().fn_name});
            }

            vertices[i] = Vertex{
                .position = math.Vec3f.init(pos[0], pos[1], pos[2]),
                .normal = math.Vec3f.init(0.0, 0.0, 1.0), // undefined
                .color = math.Vec3f.init(0.1, 0.7, 0.7),
            };
        }
    }

    return vertices;
}

fn parse_primitive_verts(
    allocator: *std.mem.Allocator,
    gltf_data: *cgltf.cgltf_data,
    primitive: cgltf.cgltf_primitive,
) ![]Vertex {
    switch (primitive.type) {
        cgltf.cgltf_primitive_type_triangles => {
            return parse_primitive_verts_type_triangles(allocator, gltf_data, primitive);
        },
        else => {
            @panic("not implemented");
        },
    }
}

pub fn load_from_file(allocator: *std.mem.Allocator, path_to_gltf_file: [*c]const u8) ![]Vertex {
    // const cgltf_memory_options = cgltf.cgltf_memory_options{
    //     .alloc_func = &zig_alloc_fn,
    //     .free_func = &zig_free_fn,
    //     .user_data = @ptrCast(allocator),
    // };

    // const cgltf_options = cgltf.cgltf_options{
    //     .type = undefined, // auto detect
    //     .json_token_count = 0, // auto
    //     .memory = cgltf_memory_options,
    //     .file = std.mem.zeroInit(cgltf.cgltf_file_options, .{}), // Could make Zig-based, this just does C defaults.
    // };
    const cgltf_options = std.mem.zeroInit(cgltf.cgltf_options, .{});

    var out_data: [*c]cgltf.cgltf_data = null;
    var result = cgltf.cgltf_parse_file(&cgltf_options, path_to_gltf_file, &out_data);
    defer cgltf.cgltf_free(out_data);
    try handle_cgltf_result(result);
    result = cgltf.cgltf_load_buffers(&cgltf_options, out_data, path_to_gltf_file);
    try handle_cgltf_result(result);

    du.log(
        "renderer",
        .debug,
        "Loaded GLTF file {s}; {d} meshes, {d} nodes",
        .{
            path_to_gltf_file,
            out_data.*.meshes_count,
            out_data.*.nodes_count,
        },
    );
    debug_print_gltf_data(out_data);

    return parse_primitive_verts(allocator, out_data, out_data.*.meshes[0].primitives[0]);
}
