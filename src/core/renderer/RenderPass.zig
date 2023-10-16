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

const RenderPass = @This();

pub const RenderPassTag = enum {
    basic_primary,
};

pub const RenderPassInfo = struct {
    renderer: *Renderer,
    window: *Window,
    enable_imgui: bool,
    tag: RenderPassTag,
};

pub fn init(info: *RenderPassInfo) !RenderPass {
    var depends_on = std.ArrayList(Resource).init(info.renderer.allocator);
    var produces = std.ArrayList(Resource).init(info.renderer.allocator);
    switch (info.tag) {
        .basic_primary => {
            const window_size = info.window.size();
            try produces.append(Resource{
                .kind = .final_texture,
                .width = window_size.width,
                .height = window_size.height,
            });
        },
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
    };
}

pub fn deinit(self: *RenderPass, renderer: *Renderer) void {
    _ = renderer;

    self.depends_on.deinit();
    self.produces.deinit();
}
