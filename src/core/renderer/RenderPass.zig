//! This is an abstraction over a "renderpass" in APIs like Vulkan. These may _not_
//! correspond one-to-one Vulkan renderpasses. Rather, this is "virtual" renderpass
//! representing a logical encapsulation for the user. They are added to the
//! `RenderGraph`, which decided which actual Vulkan renderpasses to create, along
//! with the necessary synchronization.

const std = @import("std");
const cimgui = @import("cimgui");
const vulkan = @import("vulkan");
const VulkanRenderPass = @import("vulkan//RenderPass.zig");
const Renderer = @import("./Renderer.zig");
const Resource = Renderer.Resource;
const Swapchain = @import("./Swapchain.zig");
const Window = @import("../Window.zig");

enable_imgui: bool,
depends_on: std.ArrayList(Resource),
produces: std.ArrayList(Resource),
tag: RenderPassTag,
name: []const u8,

const RenderPass = @This();

pub const RenderPassTag = enum {
    basic_primary,
    render_to_image,
};

pub const RenderPassInfo = struct {
    renderer: *Renderer,
    window: *Window,
    enable_imgui: bool,
    tag: RenderPassTag,
    produces: []Resource,
    depends_on: []Resource,
    name: []const u8,
};

pub fn init(info: *RenderPassInfo) !RenderPass {
    var depends_on = std.ArrayList(Resource).init(info.renderer.allocator);
    var i: usize = 0;
    while (i < info.depends_on.len) : (i += 1) {
        try depends_on.append(info.depends_on[i]);
    }
    var produces = std.ArrayList(Resource).init(info.renderer.allocator);
    i = 0;
    while (i < info.produces.len) : (i += 1) {
        try produces.append(info.produces[i]);
    }

    if (info.enable_imgui) {
        if (!info.window.imgui_enabled) {
            _ = cimgui.igCreateContext(null);
            info.window.imgui_enabled = true;
        }
    }

    return .{
        .enable_imgui = info.enable_imgui,
        .depends_on = depends_on,
        .produces = produces,
        .tag = info.tag,
        .name = info.name,
    };
}

pub fn deinit(self: *RenderPass, renderer: *Renderer) void {
    _ = renderer;

    self.depends_on.deinit();
    self.produces.deinit();
}
