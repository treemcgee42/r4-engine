const std = @import("std");

const r4_core = @import("r4_core");
const Core = r4_core.Core;
const Window = r4_core.Window;

const du = @import("debug_utils");

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
}
