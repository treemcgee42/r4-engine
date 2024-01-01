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

pub const ConfigFlags = packed struct(c_int) {
    nav_enable_keyboard: bool = false,
    nav_enable_gamepad: bool = false,
    nav_enable_set_mouse_pos: bool = false,
    nav_no_capture_keyboard: bool = false,

    no_mouse: bool = false,
    no_mouse_cursor_change: bool = false,
    docking_enabled: bool = false,
    viewports_enabled: bool = false,

    _: u24 = 0,
};

pub fn init(renderer: *Renderer, window: *Window, config_flags: ConfigFlags) !Ui {
    // --- Construct the Vulkan renderpass.
    // This needs to happen now so ImGUI can start receiving commands after this call.

    const window_size = window.size();
    const renderpass_init_info = VulkanSystem.StaticRenderpassCreateInfo{
        .system = &renderer.system,
        .window = window,

        .imgui_enabled = true,
        .imgui_config_flags = @bitCast(config_flags),
        .tag = .basic_primary,
        .render_area = .{
            .width = window_size.width,
            .height = window_size.height,
        },
        .name = "ImGui",
    };
    const vulkan_renderpass_handle = try renderer.system.create_static_renderpass(&renderpass_init_info);

    // ---

    return .{
        .vulkan_renderpass_handle = vulkan_renderpass_handle,
        .tmp_renderer = renderer,
    };
}

pub fn display_image_as_resource(self: *Ui, size: cimgui.ImVec2) void {
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
        size,
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

pub const ImGuiWindowFlags = packed struct(c_int) {
    no_title_bar: bool = false,
    no_resize: bool = false,
    no_move: bool = false,
    no_scrollbar: bool = false,

    no_scroll_with_mouse: bool = false,
    no_collapse: bool = false,
    always_auto_resize: bool = false,
    no_background: bool = false,

    no_saved_settings: bool = false,
    no_mouse_inputs: bool = false,
    menu_bar: bool = false,
    horizontal_scrollbar: bool = false,

    no_focus_on_appearing: bool = false,
    no_bring_to_front_on_focus: bool = false,
    always_vertical_scrollbar: bool = false,
    always_horizontal_scrollbar: bool = false,

    no_nav_inputs: bool = false,
    no_nav_focus: bool = false,
    unsaved_document: bool = false,
    no_docking: bool = false,

    _: u12 = 0,

    pub fn no_nav() ImGuiWindowFlags {
        return .{
            .no_nav_inputs = true,
            .no_nav_focus = true,
        };
    }

    pub fn no_decoration() ImGuiWindowFlags {
        return .{
            .no_title_bar = true,
            .no_resize = true,
            .no_move = true,
            .no_collapse = true,
        };
    }

    pub fn no_inputs() ImGuiWindowFlags {
        return .{
            .no_mouse_inputs = true,
            .no_nav_inputs = true,
            .no_nav_focus = true,
        };
    }
};

pub fn create_full_window_dock_space(self: *const Ui) void {
    _ = self;
    // --- Create a fullscreen window.

    const viewport = cimgui.igGetMainViewport();
    cimgui.igSetNextWindowPos(viewport.*.WorkPos, 0, .{ .x = 0, .y = 0 });
    cimgui.igSetNextWindowSize(viewport.*.WorkSize, 0);
    cimgui.igSetNextWindowViewport(viewport.*.ID);
    cimgui.igPushStyleVar_Float(cimgui.ImGuiStyleVar_WindowRounding, 0.0);
    cimgui.igPushStyleVar_Float(cimgui.ImGuiStyleVar_WindowBorderSize, 0.0);
    const window_flags = ImGuiWindowFlags{
        .menu_bar = true,
        .no_docking = true,
        .no_title_bar = true,
        .no_collapse = true,
        .no_resize = true,
        .no_move = true,
        .no_bring_to_front_on_focus = true,
        .no_nav_focus = true,
    };

    // ChatGPT:
    // Important: note that we proceed even if Begin() returns false (aka window is collapsed).
    // This is because we want to keep our DockSpace() active. If a DockSpace() is inactive,
    // all active windows docked into it will lose their parent and become undocked.
    // We cannot preserve the docking relationship between an active window and an inactive docking, otherwise
    // any change of dockspace/settings would lead to windows being stuck in limbo and never being visible.
    cimgui.igPushStyleVar_Vec2(cimgui.ImGuiStyleVar_WindowPadding, cimgui.ImVec2{ .x = 0.0, .y = 0.0 });
    _ = cimgui.igBegin("Dock space", null, @bitCast(window_flags));
    cimgui.igPopStyleVar(1);

    const dockspace_id = cimgui.igGetID_Str("Dock space");
    _ = cimgui.igDockSpace(dockspace_id, cimgui.ImVec2{ .x = 0.0, .y = 0.0 }, cimgui.ImGuiDockNodeFlags_None, null);

    cimgui.igEnd();
}
