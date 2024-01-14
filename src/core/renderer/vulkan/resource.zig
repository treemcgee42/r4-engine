const std = @import("std");
const l0vk = @import("../layer0/vulkan/vulkan.zig");
const buffer = @import("buffer.zig");
const VulkanSystem = @import("./VulkanSystem.zig");
const Window = @import("../../Window.zig");
const Renderer = @import("../Renderer.zig");

const WidthAndHeight = struct {
    width: u32,
    height: u32,
};

/// Describes the dimensions of a (e.g. attachment, texture) resource.
const Resolution = union(enum) {
    /// Absolute size in ???.
    absolute: WidthAndHeight,
    /// Specify the dimensions as some scaling of another object's dimension.
    /// This is preferred over manually calculating the scaled dimensions since
    /// we can register this relationship and update this resolution if the object
    /// being scaled against resizes.
    relative: struct {
        relative_to: enum { window },
        width_scale: f32,
        height_scale: f32,
    },

    /// Convert this resolution to an absolute resolution.
    fn to_absolute(self: Resolution, renderer: *const Renderer) WidthAndHeight {
        var to_return: WidthAndHeight = undefined;

        switch (self) {
            .absolute => |a| {
                to_return = a;
            },
            .relative => |r| {
                const base_res: WidthAndHeight = undefined;
                switch (r.relative_to) {
                    .window => {
                        const size = renderer.current_frame_context.?.window.size();
                        base_res = .{
                            .width = size.width,
                            .height = size.height,
                        };
                    },
                }

                to_return = .{
                    .width = @intFromFloat(@as(f32, @floatFromInt(base_res.width)) * r.width_scale),
                    .height = @intFromFloat(@as(f32, @floatFromInt(base_res.height)) * r.height_scale),
                };
            },
        }

        return to_return;
    }
};

pub const ResourceDescription = struct {
    /// Unique name for this resource
    name: []const u8,
    kind: Kind,
    info: Info,

    pub const Kind = enum {
        /// Testing.
        name_only,
        attachment,
        // texture,
        // buffer,
        // Means this resource has already been specified somewhere else,
        // and we want to reuse it.
        // reference,
    };

    pub const Info = union(Kind) {
        name_only: void,
        attachment: AttachmentInfo,
    };

    pub const AttachmentInfo = struct {
        kind: AttachmentKind,
        format: l0vk.VkFormat,
        resolution: Resolution,
        clear_color: [4]f32 = .{ 1, 0, 1, 1 },

        const AttachmentKind = enum {
            color,
            depth,
        };
    };
};

const ResourceSystem = struct {
    resource_descriptions: std.StringHashMap(ResourceDescription),
    vulkan_resources: std.StringHashMap(VulkanResources),

    pub fn init(allocator: std.mem.Allocator) ResourceSystem {
        const resources_descriptions = std.StringHashMap(ResourceDescription).init(allocator);
        const vulkan_resources = std.StringHashMap(VulkanResources).init(allocator);

        return .{
            .resources_descriptions = resources_descriptions,
            .vulkan_resources = vulkan_resources,
        };
    }

    pub fn deinit(self: *ResourceSystem, vulkan_system: *VulkanSystem) void {
        self.resource_descriptions.deinit();

        var i: usize = 0;
        while (i < self.vulkan_resources.items.len) : (i += 1) {
            self.vulkan_resources.items[i].deinit(vulkan_system);
        }

        self.vulkan_resources.deinit();
    }

    pub fn create_resource(
        self: *ResourceSystem,
        description: ResourceDescription,
    ) void {
        try self.resource_descriptions.put(description.name, description);
    }
};

const VulkanResources = union(enum) {
    not_allocated,
    attachment: VulkanAttachmentResources,

    fn deinit(self: VulkanResources, system: *VulkanSystem) void {
        switch (self) {
            .attachment => |a| {
                a.image.deinit(system.logical_device, system.vma_allocator);
            },
        }
    }
};

const VulkanAttachmentResources = struct {
    image: union(enum) {
        color: buffer.ColorImage,
        depth: buffer.DepthImage,
    },
    attachment: l0vk.VkRenderingAttachmentInfo,
};

/// Creates Vulkan resources to represent a resource.
/// - For attachments, this will create both the image and the attachment.
///
/// User is responsible for freeing all returned resources when done.
fn attachment_resource_to_vulkan_resources(
    renderer: *Renderer,
    resource_description: ResourceDescription,
) !VulkanAttachmentResources {
    const system = renderer.system;
    const resolution = resource_description.info.attachment.resolution.to_absolute(renderer);

    switch (resource_description.info.attachment.kind) {
        .color => {
            const format = @intFromEnum(resource_description.info.attachment.format);

            const image = try buffer.ColorImage.init(
                system.physical_device,
                system.logical_device,
                system.vma_allocator,
                resolution.width,
                resolution.height,
                format,
                @bitCast(l0vk.VkSampleCountFlags{ .bit_1 = true }),
                @bitCast(l0vk.VkImageUsageFlags{ .color_attachment = true, .sampled = true }),
            );

            const color_attachment_info = l0vk.VkRenderingAttachmentInfo{
                .imageView = image.image_view,
                .imageLayout = .color_attachment_optimal,
                .loadOp = .clear,
                .storeOp = .store,
                .clearValue = .{ .color = .{ .float32 = resource_description.info.attachment.clear_color } },

                .resolveImageLayout = .undefined,
                .resolveImageView = null,
            };

            return VulkanAttachmentResources{
                .image = .{ .color = image },
                .attachment = color_attachment_info,
            };
        },
        .depth => {
            const image = try buffer.DepthImage.init(
                system.physical_device,
                system.logical_device,
                system.vma_allocator,
                resolution.width,
                resolution.height,
                1,
            );

            const attachment_info = l0vk.VkRenderingAttachmentInfo{
                .imageView = image.image_view,
                .imageLayout = .depth_stencil_attachment_optimal,
                .loadOp = .clear,
                .storeOp = .store,
                .clearValue = .{
                    .depthStencil = .{
                        .depth = 1.0,
                        .stencil = 0,
                    },
                },

                .resolveImageLayout = .undefined,
                .resolveImageView = null,
            };

            return VulkanAttachmentResources{
                .image = .{ .depth = image },
                .attachment = attachment_info,
            };
        },
    }
}
