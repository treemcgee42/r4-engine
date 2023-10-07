const std = @import("std");
const vulkan = @import("vulkan");
const Context = @import("./Context.zig");
const Window = @import("../Window.zig");
const Core = @import("../Core.zig");
const Swapchain = @import("./Swapchain.zig");

pub const RendererApiContext = struct {
    command_buffer: vulkan.VkCommandBuffer,
    image_index: u32,
};

pub fn begin_recording(core: *Core, window: *Window) !RendererApiContext {
    switch (core.renderer_context.backend) {
        .vulkan => {
            var swapchain = &window.swapchain.swapchain.vulkan;
            var system = core.renderer_context.system.vulkan;

            // --- Wait for the previous frame to finish.

            var result = vulkan.vkWaitForFences(
                core.renderer_context.system.vulkan.logical_device,
                1,
                &swapchain.in_flight_fences[swapchain.current_frame],
                vulkan.VK_TRUE,
                std.math.maxInt(u64),
            );
            if (result != vulkan.VK_SUCCESS) {
                unreachable;
            }

            // --- Acquire the next image.

            var image_index: u32 = undefined;
            result = vulkan.vkAcquireNextImageKHR(
                system.logical_device,
                swapchain.swapchain,
                std.math.maxInt(u64),
                swapchain.image_available_semaphores[swapchain.current_frame],
                @ptrCast(vulkan.VK_NULL_HANDLE),
                &image_index,
            );
            if (result != vulkan.VK_SUCCESS and result != vulkan.VK_SUBOPTIMAL_KHR) {
                switch (result) {
                    vulkan.VK_ERROR_OUT_OF_DATE_KHR => {
                        try window.recreate_swapchain_callback(core);
                        return begin_recording(core, window);
                    },
                    else => unreachable,
                }
            }

            // --- Reset the fence if submitting work.

            result = vulkan.vkResetFences(
                system.logical_device,
                1,
                &swapchain.in_flight_fences[swapchain.current_frame],
            );
            if (result != vulkan.VK_SUCCESS) {
                unreachable;
            }

            // ---

            var p_command_buffer = &system.command_buffers[swapchain.current_frame];

            result = vulkan.vkResetCommandBuffer(p_command_buffer.*, 0);
            if (result != vulkan.VK_SUCCESS) {
                unreachable;
            }

            // --- Begin command buffer.

            const begin_info = vulkan.VkCommandBufferBeginInfo{
                .sType = vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                .flags = 0,
                .pInheritanceInfo = null,
                .pNext = null,
            };

            result = vulkan.vkBeginCommandBuffer(p_command_buffer.*, &begin_info);
            if (result != vulkan.VK_SUCCESS) {
                unreachable;
            }

            // ---

            return .{
                .command_buffer = p_command_buffer.*,
                .image_index = image_index,
            };
        },
    }
}

pub fn end_recording(core: *Core, window: *Window, context: RendererApiContext) !void {
    switch (core.renderer_context.backend) {
        .vulkan => {
            var swapchain = &window.swapchain.swapchain.vulkan;
            var p_command_buffer = &context.command_buffer;

            // --- End command buffer.

            var result = vulkan.vkEndCommandBuffer(context.command_buffer);
            if (result != vulkan.VK_SUCCESS) {
                unreachable;
            }

            // --- Submit command buffer.

            const wait_semaphores = [_]vulkan.VkSemaphore{swapchain.image_available_semaphores[swapchain.current_frame]};
            const wait_stages = [_]vulkan.VkPipelineStageFlags{
                vulkan.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            };
            const signal_semaphores = [_]vulkan.VkSemaphore{
                swapchain.render_finished_semaphores[swapchain.current_frame],
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
                core.renderer_context.system.vulkan.graphics_queue,
                1,
                &submit_info,
                swapchain.in_flight_fences[swapchain.current_frame],
            );
            if (result != vulkan.VK_SUCCESS) {
                unreachable;
            }

            // --- Present.

            const swapchains = [_]vulkan.VkSwapchainKHR{swapchain.swapchain};
            const present_info = vulkan.VkPresentInfoKHR{
                .sType = vulkan.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
                .waitSemaphoreCount = 1,
                .pWaitSemaphores = signal_semaphores[0..].ptr,
                .swapchainCount = swapchains.len,
                .pSwapchains = swapchains[0..].ptr,
                .pImageIndices = &context.image_index,

                .pResults = null,
                .pNext = null,
            };

            result = vulkan.vkQueuePresentKHR(core.renderer_context.system.vulkan.present_queue, &present_info);
            if (result != vulkan.VK_SUCCESS) {
                switch (result) {
                    vulkan.VK_ERROR_OUT_OF_DATE_KHR => {
                        try window.recreate_swapchain_callback(core);
                    },
                    vulkan.VK_SUBOPTIMAL_KHR => {
                        try window.recreate_swapchain_callback(core);
                    },
                    else => unreachable,
                }
            }

            if (window.framebuffer_resized) {
                window.framebuffer_resized = false;
                try window.recreate_swapchain_callback(core);
            }

            swapchain.current_frame = (swapchain.current_frame + 1) % Swapchain.max_frames_in_flight;
        },
    }
}
