const std = @import("std");
const vulkan = @import("vulkan");
const vulkan_pipeline = @import("vulkan/pipeline.zig");
const Renderer = @import("./Renderer.zig");
const RenderPass = @import("RenderPass.zig");

pub const PipelineInfo = struct {
    name: []const u8,

    render_pass: Renderer.RenderPassHandle,

    vertex_shader_filename: []const u8,
    fragment_shader_filename: []const u8,
    topology: Topology,
    front_face_orientation: FrontFaceOrientation,

    pub const Topology = enum {
        triangle_list,
    };

    pub const FrontFaceOrientation = enum {
        counter_clockwise,
        clockwise,
    };
};

pub const Pipeline = union {
    vulkan: vulkan.VkPipeline,
};

pub const PipelineSystem = struct {
    pipeline_infos: std.ArrayList(PipelineInfo),
    pipeline_handles: std.StringHashMap(PipelineHandle),
    pipelines: std.AutoHashMap(PipelineHandle, Pipeline),

    pub const PipelineHandle = usize;

    pub fn init(allocator: std.mem.Allocator) !PipelineSystem {
        return .{
            .pipeline_infos = std.ArrayList(PipelineInfo).init(allocator),
            .pipeline_handles = std.StringHashMap(PipelineHandle).init(allocator),
            .pipelines = std.AutoHashMap(PipelineHandle, Pipeline).init(allocator),
        };
    }

    pub fn deinit(self: *PipelineSystem, renderer: *Renderer) void {
        self.pipeline_infos.deinit();
        self.pipeline_handles.deinit();

        var pipelines_iter = self.pipelines.iterator();
        while (pipelines_iter.next()) |entry| {
            switch (renderer.backend) {
                .vulkan => {
                    vulkan.vkDestroyPipeline(renderer.system.vulkan.logical_device, entry.value_ptr.*.vulkan, null);
                },
            }
        }
        self.pipelines.deinit();
    }

    /// Tries to find a corresponding pipeline in cache, otherwise builds it.
    pub fn query(self: *PipelineSystem, renderer: *Renderer, info: PipelineInfo) !PipelineHandle {
        var handle = self.pipeline_handles.get(info.name);
        if (handle != null) {
            return handle.?;
        }

        try self.pipeline_infos.append(info);
        handle = self.pipeline_infos.items.len - 1;
        const pipeline = try build_pipeline(renderer, info);
        try self.pipelines.put(handle.?, pipeline);
        try self.pipeline_handles.put(info.name, handle.?);
        return handle.?;
    }

    fn build_pipeline(renderer: *Renderer, info: PipelineInfo) !Pipeline {
        const raw_pipeline = switch (renderer.backend) {
            .vulkan => try vulkan_pipeline.build_pipeline(renderer, info),
        };

        return switch (renderer.backend) {
            .vulkan => .{
                .vulkan = raw_pipeline,
            },
        };
    }
};
