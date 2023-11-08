const Renderer = @import("./Renderer.zig");
const Window = @import("../Window.zig");
const VulkanSystem = @import("vulkan/VulkanSystem.zig");
const cimgui = @import("cimgui");
const vulkan = @import("vulkan");

const Ui = @This();

vulkan_renderpass_handle: usize,

tmp_uploaded_image: bool = false,
tmp_renderer: *Renderer,
tmp_imgui_return: ?vulkan.VkDescriptorSet = null,

pub fn init(renderer: *Renderer, window: *Window) !Ui {
    // --- Construct the Vulkan renderpass.
    // This needs to happen now so ImGUI can start receiving commands after this call.

    const window_size = window.size();
    const renderpass_init_info = VulkanSystem.RenderPassInitInfo{
        .system = &renderer.system,
        .window = window,

        .imgui_enabled = true,
        .tag = .basic_primary,
        .render_area = .{
            .width = window_size.width,
            .height = window_size.height,
        },
        .name = "ImGui",
    };
    const vulkan_renderpass_handle = try renderer.system.create_renderpass(&renderpass_init_info);

    // ---

    return .{
        .vulkan_renderpass_handle = vulkan_renderpass_handle,
        .tmp_renderer = renderer,
    };
}

pub fn display_image_as_resource(self: *Ui) void {
    if (self.tmp_renderer.system.tmp_image == null) {
        return;
    }

    const image = self.tmp_renderer.system.tmp_image.?;
    if (!self.tmp_uploaded_image) {
        self.tmp_imgui_return = @as(vulkan.VkDescriptorSet, @ptrCast(cimgui.ImGui_ImplVulkan_AddTexture(
            @ptrCast(image.sampler.?),
            @ptrCast(image.image_view),
            vulkan.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        )));
        self.tmp_uploaded_image = true;
    }

    cimgui.igImage(
        @ptrCast(self.tmp_imgui_return.?),
        cimgui.ImVec2{
            .x = @floatFromInt(image.image.width),
            .y = @floatFromInt(image.image.height),
        },
        cimgui.ImVec2{ // default uv0
            .x = 0,
            .y = 0,
        },
        cimgui.ImVec2{ // default uv1
            .x = 1,
            .y = 1,
        },
        cimgui.ImVec4{ // default tint
            .x = 1,
            .y = 1,
            .z = 1,
            .w = 1,
        },
        cimgui.ImVec4{ // default border
            .x = 0,
            .y = 0,
            .z = 0,
            .w = 0,
        },
    );
}
