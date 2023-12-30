const std = @import("std");
const vulkan = @import("vulkan");
const vulkan_pipeline = @import("vulkan/pipeline.zig");
const Renderer = @import("./Renderer.zig");
const RenderPass = @import("RenderPass.zig");

pub const Pipeline = struct {
    name: []const u8,

    render_pass: Renderer.RenderPassHandle,

    vertex_shader_filename: []const u8,
    fragment_shader_filename: []const u8,
    topology: Topology,
    front_face_orientation: FrontFaceOrientation,
    depth_test_enabled: bool = false,

    pub const Topology = enum {
        triangle_list,
    };

    pub const FrontFaceOrientation = enum {
        counter_clockwise,
        clockwise,
    };
};
