const std = @import("std");
const l0vk = @import("../layer0/vulkan/vulkan.zig");
const vulkan = @import("vulkan");
const buffer = @import("buffer.zig");
const VulkanSystem = @import("./VulkanSystem.zig");
const Window = @import("../../Window.zig");
const Renderer = @import("../Renderer.zig");
const dutil = @import("debug_utils");

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
    fn to_absolute(self: Resolution, window: *const Window) WidthAndHeight {
        var to_return: WidthAndHeight = undefined;

        switch (self) {
            .absolute => |a| {
                to_return = a;
            },
            .relative => |r| {
                var base_res: WidthAndHeight = undefined;
                switch (r.relative_to) {
                    .window => {
                        const size = window.get_size_pixels();
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
    };
};

pub const AttachmentKind = enum {
    color,
    color_final,
    depth,
};

pub const ResourceSystem = struct {
    resource_descriptions: std.StringHashMap(ResourceDescription),
    vulkan_resources: std.StringHashMap(VulkanResources),

    const Error = error{
        resource_not_found,
    } || std.mem.Allocator.Error;

    pub fn init(allocator: std.mem.Allocator) ResourceSystem {
        const resource_descriptions = std.StringHashMap(ResourceDescription).init(allocator);
        const vulkan_resources = std.StringHashMap(VulkanResources).init(allocator);

        return .{
            .resource_descriptions = resource_descriptions,
            .vulkan_resources = vulkan_resources,
        };
    }

    pub fn deinit(self: *ResourceSystem, vulkan_system: *VulkanSystem) void {
        self.resource_descriptions.deinit();

        var iter = self.vulkan_resources.valueIterator();
        while (iter.next()) |vulkan_resource| {
            vulkan_resource.deinit(vulkan_system);
        }

        self.vulkan_resources.deinit();
    }

    pub fn destroy_resource(
        self: *ResourceSystem,
        vulkan_system: *VulkanSystem,
        name: []const u8,
    ) void {
        _ = self.resource_descriptions.remove(name);
        const vulkan_resources = self.vulkan_resources.get(name);
        if (vulkan_resources != null) {
            vulkan_resources.?.deinit(vulkan_system);
        }
    }

    pub fn create_resource(
        self: *ResourceSystem,
        description: ResourceDescription,
    ) !void {
        try self.resource_descriptions.put(description.name, description);
    }

    pub fn create_vulkan_resources(
        self: *ResourceSystem,
        renderer: *Renderer,
        window: *Window,
        resource_name: []const u8,
    ) !void {
        const description = self.resource_descriptions.get(resource_name) orelse {
            return Error.resource_not_found;
        };

        var vulkan_resource: VulkanResources = undefined;
        switch (description.kind) {
            .name_only => {
                vulkan_resource = .not_allocated;
            },
            .attachment => {
                vulkan_resource = .{
                    .attachment = try attachment_resource_to_vulkan_resources(
                        renderer,
                        window,
                        description,
                    ),
                };
            },
        }

        try self.vulkan_resources.put(resource_name, vulkan_resource);
    }

    pub fn get_image_view(
        self: *ResourceSystem,
        resource_name: []const u8,
    ) !l0vk.VkImageView {
        const resource = self.vulkan_resources.get(resource_name) orelse {
            return Error.resource_not_found;
        };

        switch (resource) {
            .attachment => {
                return resource.attachment.get_image_view();
            },
            else => {
                dutil.log(
                    "resource system",
                    .err,
                    "resource {s} is not an attachment",
                    .{resource_name},
                );
                return Error.resource_not_found;
            },
        }
    }

    pub fn get_image_sampler(
        self: *ResourceSystem,
        resource_name: []const u8,
    ) !vulkan.VkSampler {
        const resource = self.vulkan_resources.get(resource_name) orelse {
            return Error.resource_not_found;
        };

        switch (resource) {
            .attachment => {
                return resource.attachment.get_image_sampler();
            },
            else => {
                dutil.log(
                    "resource system",
                    .err,
                    "resource {s} is not an attachment",
                    .{resource_name},
                );
                return Error.resource_not_found;
            },
        }
    }

    pub fn is_attachment(
        self: *ResourceSystem,
        resource_name: []const u8,
    ) bool {
        const resource = self.resource_descriptions.get(resource_name) orelse {
            dutil.log(
                "resource system",
                .warn,
                "resource {s} not found, while checking if it was an attachment",
                .{resource_name},
            );
            return false;
        };

        switch (resource.kind) {
            .attachment => {
                return true;
            },
            else => {
                return false;
            },
        }
    }

    pub fn get_attachment_kind(
        self: *ResourceSystem,
        resource_name: []const u8,
    ) !AttachmentKind {
        const resource = self.resource_descriptions.get(resource_name) orelse {
            return Error.resource_not_found;
        };

        switch (resource.kind) {
            .attachment => {
                return resource.info.attachment.kind;
            },
            else => {
                return Error.resource_not_found;
            },
        }
    }

    pub fn get_attachment_format(
        self: *ResourceSystem,
        resource_name: []const u8,
    ) !l0vk.VkFormat {
        const resource = self.resource_descriptions.get(resource_name) orelse {
            return Error.resource_not_found;
        };

        switch (resource.kind) {
            .attachment => {
                return resource.info.attachment.format;
            },
            else => {
                return Error.resource_not_found;
            },
        }
    }

    pub fn is_color_attachment(
        self: *ResourceSystem,
        resource_name: []const u8,
    ) bool {
        const resource = self.resource_descriptions.get(resource_name) orelse {
            dutil.log(
                "resource system",
                .warn,
                "resource {s} not found, while checking if it was a color attachment",
                .{resource_name},
            );
            return false;
        };

        switch (resource.kind) {
            .attachment => {
                return resource.info.attachment.kind == .color;
            },
            else => {
                return false;
            },
        }
    }

    pub fn is_depth_attachment(
        self: *ResourceSystem,
        resource_name: []const u8,
    ) bool {
        const resource = self.resource_descriptions.get(resource_name) orelse {
            dutil.log(
                "resource system",
                .warn,
                "resource {s} not found, while checking if it was a depth attachment",
                .{resource_name},
            );
            return false;
        };

        switch (resource.kind) {
            .attachment => {
                return resource.info.attachment.kind == .depth;
            },
            else => {
                return false;
            },
        }
    }

    pub fn get_width_and_height(
        self: *ResourceSystem,
        resource_name: []const u8,
        renderer: *const Renderer,
        window: *const Window,
    ) !WidthAndHeight {
        _ = renderer;

        if (!self.is_attachment(resource_name)) {
            dutil.log(
                "resource system",
                .err,
                "{s}: resource {s} is not an attachment",
                .{ @src().fn_name, resource_name },
            );
        }

        const attachment_kind = self.get_attachment_kind(resource_name) catch {
            return Error.resource_not_found;
        };
        if (attachment_kind != .color and attachment_kind != .color_final) {
            dutil.log(
                "resource system",
                .err,
                "{s}: resource is a {s} attachment",
                .{ @src().fn_name, @tagName(attachment_kind) },
            );
            return Error.resource_not_found;
        }

        const resource_desc = self.resource_descriptions.get(resource_name) orelse {
            return Error.resource_not_found;
        };

        return resource_desc.info.attachment.resolution.to_absolute(window);
    }

    pub fn transition_image_layout(
        self: *ResourceSystem,
        renderer: *Renderer,
        command_buffer: l0vk.VkCommandBuffer,
        resource_name: []const u8,
        old_layout: vulkan.VkImageLayout,
        new_layout: vulkan.VkImageLayout,
    ) !void {
        const resource = self.vulkan_resources.getPtr(resource_name) orelse {
            dutil.log(
                "resource system",
                .err,
                "{s}: resource {s} not found",
                .{ @src().fn_name, resource_name },
            );
            return;
        };

        switch (resource.*) {
            .not_allocated => {},
            .attachment => {
                var vulkan_resources = &resource.attachment;

                switch (vulkan_resources.image) {
                    .color_final => {
                        try buffer.transition_image_layout_base(
                            renderer.system.swapchain.swapchain_images[
                                renderer.current_frame_context.?.image_index
                            ],
                            command_buffer,
                            old_layout,
                            new_layout,
                            1,
                        );
                    },
                    .color => {
                        try vulkan_resources.image.color.image.transition_image_layout(
                            command_buffer,
                            old_layout,
                            new_layout,
                        );
                    },
                    .depth => {
                        @panic("not implemented");
                    },
                }
            },
        }
    }
};

const VulkanResources = union(enum) {
    not_allocated,
    attachment: VulkanAttachmentResources,

    fn deinit(self: VulkanResources, system: *VulkanSystem) void {
        switch (self) {
            .not_allocated => {},
            .attachment => |a| {
                a.deinit(system.logical_device, system.vma_allocator);
            },
        }
    }
};

const VulkanAttachmentResources = struct {
    image: union(enum) {
        color_final,
        color: buffer.ColorImage,
        depth: buffer.DepthImage,
    },

    fn get_image_view(self: VulkanAttachmentResources) l0vk.VkImageView {
        return switch (self.image) {
            .color_final => {
                dutil.log(
                    "resource system",
                    .err,
                    "calling get_image_view on color_final (it's not stored here)",
                    .{},
                );
                @panic("bad");
            },
            .color => |c| c.image_view,
            .depth => |d| d.image_view,
        };
    }

    fn get_image_sampler(self: VulkanAttachmentResources) vulkan.VkSampler {
        return switch (self.image) {
            .color_final, .depth => {
                dutil.log(
                    "resource system",
                    .err,
                    "calling get_image_view on color_final (it's not stored here)",
                    .{},
                );
                @panic("bad");
            },
            .color => |c| c.sampler.?,
        };
    }

    fn deinit(
        self: VulkanAttachmentResources,
        logical_device: l0vk.VkDevice,
        vma_allocator: VulkanSystem.VmaAllocator,
    ) void {
        switch (self.image) {
            .color_final => {},
            .color => |c| {
                c.deinit(logical_device, vma_allocator);
            },
            .depth => |d| {
                d.deinit(logical_device, vma_allocator);
            },
        }
    }
};

/// Creates Vulkan resources to represent a resource.
/// - For attachments, this will create both the image and the attachment.
///
/// User is responsible for freeing all returned resources when done.
fn attachment_resource_to_vulkan_resources(
    renderer: *Renderer,
    window: *Window,
    resource_description: ResourceDescription,
) !VulkanAttachmentResources {
    const system = renderer.system;
    const resolution = resource_description.info.attachment.resolution.to_absolute(window);

    switch (resource_description.info.attachment.kind) {
        .color_final => {
            return .{
                .image = .{ .color_final = {} },
            };
        },
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

            // const color_attachment_info = l0vk.VkRenderingAttachmentInfo{
            //     .imageView = image.image_view,
            //     .imageLayout = .color_attachment_optimal,
            //     .loadOp = .clear,
            //     .storeOp = .store,
            //     .clearValue = .{ .color = .{ .float32 = resource_description.info.attachment.clear_color } },

            //     .resolveImageLayout = .undefined,
            //     .resolveImageView = null,
            // };

            return VulkanAttachmentResources{
                .image = .{ .color = image },
                // .attachment = color_attachment_info,
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

            // const attachment_info = l0vk.VkRenderingAttachmentInfo{
            //     .imageView = image.image_view,
            //     .imageLayout = .depth_stencil_attachment_optimal,
            //     .loadOp = .clear,
            //     .storeOp = .store,
            //     .clearValue = .{
            //         .depthStencil = .{
            //             .depth = 1.0,
            //             .stencil = 0,
            //         },
            //     },

            //     .resolveImageLayout = .undefined,
            //     .resolveImageView = null,
            // };

            return VulkanAttachmentResources{
                .image = .{ .depth = image },
                // .attachment = attachment_info,
            };
        },
    }
}
