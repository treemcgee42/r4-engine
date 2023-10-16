const Renderer = @import("./Renderer.zig");
const Window = @import("../Window.zig");

const Ui = @This();

vulkan_renderpass_handle: usize,

pub fn enable_ui(renderer: *Renderer, window: *Window) !Ui {
    // --- Construct the Vulkan renderpass.
    // This needs to happen now so ImGUI can start receiving commands after this call.

    const window_size = window.size();
    const renderpass_init_info = .{
        .system = renderer.system,
        .window = window,

        .imgui_enabled = true,
        .tag = .basic_primary,
        .render_area = .{
            .width = window_size.width,
            .height = window_size.height,
        },
    };
    const vulkan_renderpass_handle = try renderer.system.create_renderpass(&renderpass_init_info);

    // ---

    return .{
        .vulkan_renderpass_handle = vulkan_renderpass_handle,
    };
}
