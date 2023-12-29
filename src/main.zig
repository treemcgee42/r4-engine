const std = @import("std");
const builtin = @import("builtin");
const du = @import("debug_utils");

const glfw = @import("c.zig").glfw;
const cglm = @import("c.zig").cglm;

const Window = @import("core/Window.zig");

const Math = @import("math.zig");

const Core = @import("core/Core.zig");
const RenderPass = @import("core/renderer/RenderPass.zig");

const WIDTH: u32 = 800;
const HEIGHT: u32 = 600;

// ---

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var core = try Core.init(allocator);
    defer core.deinit();
    du.log("core", .info, "r4 core intialized", .{});

    const window_init_info = Window.WindowInitInfo{};
    var window = try Window.init(&core, &window_init_info);
    window.setup_resize();

    try window.run_main_loop(&core);
    defer window.deinit(&core);

    core.renderer.system.prep_for_deinit();

    // var app = try HelloTriangleApp.init(allocator);
    // app.setup_resize();
    // defer app.deinit();
    //
    // try app.run();
}
