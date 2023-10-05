const std = @import("std");
const glfw = @import("../c/glfw.zig");
const cimgui = @import("../c/cimgui.zig");
const vulkan = @import("../c/vulkan.zig");
const Core = @import("Core.zig");
const VulkanSystem = @import("vulkan/VulkanSystem.zig");
const VulkanError = @import("vulkan/VulkanSystem.zig").VulkanError;
const Swapchain = @import("vulkan/Swapchain.zig");
const RenderPass = @import("vulkan/RenderPass.zig");

const Window = @This();

window: *glfw.GLFWwindow,
surface: vulkan.VkSurfaceKHR,
framebuffer_resized: bool,

swapchain: Swapchain,

render_passes: std.ArrayList(RenderPass),

show_imgui_demo_window: bool = true,

pub const WindowInitInfo = struct {
    width: u32 = 800,
    height: u32 = 600,
    name: []const u8 = "Untitled Window",
};

pub const WindowInitError = error{
    glfw_init_failed,
    glfw_create_window_failed,
    surface_creation_failed,
    swapchain_creation_failed,
};

/// Note GLFW must be initialized beforehand, e.g. call `glfw.glfwInit()` before trying to
/// create a window
pub fn init(core: *Core, info: *const WindowInitInfo) WindowInitError!Window {
    // ---

    glfw.glfwWindowHint(glfw.GLFW_CLIENT_API, glfw.GLFW_NO_API);
    glfw.glfwWindowHint(glfw.GLFW_RESIZABLE, glfw.GLFW_TRUE);

    const maybe_window = glfw.glfwCreateWindow(
        @intCast(info.width),
        @intCast(info.height),
        @ptrCast(info.name),
        null,
        null,
    );
    if (maybe_window == null) {
        return WindowInitError.glfw_create_window_failed;
    }

    const surface = VulkanSystem.create_surface(core.vulkan_system.instance, maybe_window.?) catch {
        return WindowInitError.surface_creation_failed;
    };

    // ---

    const swapchain = Swapchain.init(core, surface) catch {
        return WindowInitError.swapchain_creation_failed;
    };

    const render_passes = std.ArrayList(RenderPass).init(core.allocator);

    // ---

    return .{
        .window = maybe_window.?,
        .surface = surface,
        .framebuffer_resized = false,

        .swapchain = swapchain,

        .render_passes = render_passes,
    };
}

pub const WindowRunError = error{
    draw_frame_failed,
};

pub fn run_main_loop(self: *Window, core: *Core) WindowRunError!void {
    while (glfw.glfwWindowShouldClose(self.window) == 0) {
        glfw.glfwPollEvents();

        cimgui.ImGui_ImplVulkan_NewFrame();
        cimgui.ImGui_ImplGlfw_NewFrame();

        cimgui.igNewFrame();

        if (self.show_imgui_demo_window) {
            cimgui.igShowDemoWindow(&self.show_imgui_demo_window);
        }

        cimgui.igRender();

        self.draw_frame(core) catch {
            return WindowRunError.draw_frame_failed;
        };
    }
}

pub fn deinit(self: *Window, core: *Core) void {
    var i: usize = 0;
    while (i < self.render_passes.items.len) : (i += 1) {
        self.render_passes.items[i].deinit(core);
    }
    self.render_passes.deinit();

    self.swapchain.deinit(core);

    vulkan.vkDestroySurfaceKHR(core.vulkan_system.instance, self.surface, null);
    glfw.glfwDestroyWindow(self.window);
}

pub fn add_renderpass(self: *Window, render_pass: RenderPass) void {
    self.render_passes.append(render_pass) catch unreachable;
}

pub fn draw_frame(self: *Window, core: *Core) VulkanError!void {
    // --- Wait for the previous frame to finish.

    var result = vulkan.vkWaitForFences(
        core.vulkan_system.logical_device,
        1,
        &self.swapchain.in_flight_fences[self.swapchain.current_frame],
        vulkan.VK_TRUE,
        std.math.maxInt(u64),
    );
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }

    // --- Acquire the next image.

    var image_index: u32 = undefined;
    result = vulkan.vkAcquireNextImageKHR(
        core.vulkan_system.logical_device,
        self.swapchain.swapchain,
        std.math.maxInt(u64),
        self.swapchain.image_available_semaphores[self.swapchain.current_frame],
        @ptrCast(vulkan.VK_NULL_HANDLE),
        &image_index,
    );
    if (result != vulkan.VK_SUCCESS and result != vulkan.VK_SUBOPTIMAL_KHR) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_DATE_KHR => {
                try self.recreate_swapchain_callback(core);
                return;
            },
            else => unreachable,
        }
    }

    // --- Reset the fence if submitting work.

    result = vulkan.vkResetFences(
        core.vulkan_system.logical_device,
        1,
        &self.swapchain.in_flight_fences[self.swapchain.current_frame],
    );
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }

    // --- Record command buffer.

    var p_command_buffer = &core.vulkan_system.command_buffers[self.swapchain.current_frame];

    result = vulkan.vkResetCommandBuffer(p_command_buffer.*, 0);
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }

    try self.record_command_buffer(p_command_buffer.*, image_index);

    // --- Submit command buffer.

    const wait_semaphores = [_]vulkan.VkSemaphore{self.swapchain.image_available_semaphores[self.swapchain.current_frame]};
    const wait_stages = [_]vulkan.VkPipelineStageFlags{
        vulkan.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
    };
    const signal_semaphores = [_]vulkan.VkSemaphore{
        self.swapchain.render_finished_semaphores[self.swapchain.current_frame],
    };

    const submit_info = vulkan.VkSubmitInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = wait_semaphores.len,
        .pWaitSemaphores = wait_semaphores[0..].ptr,
        .pWaitDstStageMask = wait_stages[0..].ptr,
        .commandBufferCount = 1,
        .pCommandBuffers = p_command_buffer,
        .signalSemaphoreCount = signal_semaphores.len,
        .pSignalSemaphores = signal_semaphores[0..].ptr,

        .pNext = null,
    };

    result = vulkan.vkQueueSubmit(
        core.vulkan_system.graphics_queue,
        1,
        &submit_info,
        self.swapchain.in_flight_fences[self.swapchain.current_frame],
    );
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }

    // --- Present.

    const swapchains = [_]vulkan.VkSwapchainKHR{self.swapchain.swapchain};
    const present_info = vulkan.VkPresentInfoKHR{
        .sType = vulkan.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = signal_semaphores[0..].ptr,
        .swapchainCount = swapchains.len,
        .pSwapchains = swapchains[0..].ptr,
        .pImageIndices = &image_index,

        .pResults = null,
        .pNext = null,
    };

    result = vulkan.vkQueuePresentKHR(core.vulkan_system.present_queue, &present_info);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_DATE_KHR => {
                try self.recreate_swapchain_callback(core);
            },
            vulkan.VK_SUBOPTIMAL_KHR => {
                try self.recreate_swapchain_callback(core);
            },
            else => unreachable,
        }
    }

    if (self.framebuffer_resized) {
        self.framebuffer_resized = false;
        try self.recreate_swapchain_callback(core);
    }

    self.swapchain.current_frame = (self.swapchain.current_frame + 1) % Swapchain.max_frames_in_flight;
}

fn record_command_buffer(self: *Window, command_buffer: vulkan.VkCommandBuffer, image_index: u32) VulkanError!void {
    // --- Begin command buffer.

    const begin_info = vulkan.VkCommandBufferBeginInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = 0,
        .pInheritanceInfo = null,
        .pNext = null,
    };

    var result = vulkan.vkBeginCommandBuffer(command_buffer, &begin_info);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            else => unreachable,
        }
    }

    // --- Begin render pass.

    var i: usize = 0;
    while (i < self.render_passes.items.len) : (i += 1) {
        var render_pass = self.render_passes.items[i];
        render_pass.record_commands(self, command_buffer, image_index);
    }

    // --- End command buffer.

    result = vulkan.vkEndCommandBuffer(command_buffer);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            else => unreachable,
        }
    }
}

pub fn setup_resize(self: *Window) void {
    glfw.glfwSetWindowUserPointer(self.window, self);
    _ = glfw.glfwSetFramebufferSizeCallback(self.window, window_resize_callback);
}

fn window_resize_callback(window: ?*glfw.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    _ = height;
    _ = width;
    var app: *Window = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(window)));
    app.framebuffer_resized = true;
}

fn recreate_swapchain_callback(self: *Window, core: *Core) VulkanError!void {
    const swapchain_settings = try Swapchain.query_swapchain_settings(
        core.allocator,
        core.vulkan_system.physical_device,
        core.vulkan_system.logical_device,
        self.surface,
    );
    try self.swapchain.recreate_swapchain(core, swapchain_settings, self.window);

    var i: usize = 0;
    while (i < self.render_passes.items.len) : (i += 1) {
        try self.render_passes.items[i].recreate_swapchain_callback(self, core);
    }
}
