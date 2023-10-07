const std = @import("std");
const glfw = @import("glfw");
const vulkan = @import("vulkan");
const VulkanError = @import("./VulkanSystem.zig").VulkanError;
const SwapchainSettings = @import("./VulkanSystem.zig").SwapchainSettings;
pub const query_swapchain_settings = @import("./VulkanSystem.zig").query_swapchain_settings;
const buffer = @import("./buffer.zig");
const RenderPass = @import("./RenderPass.zig");
const VulkanSystem = @import("./VulkanSystem.zig");

const Swapchain = @This();

swapchain: vulkan.VkSwapchainKHR,
swapchain_images: []vulkan.VkImage,
swapchain_image_format: vulkan.VkFormat,
swapchain_extent: vulkan.VkExtent2D,
swapchain_image_views: []vulkan.VkImageView,

image_available_semaphores: []vulkan.VkSemaphore,
render_finished_semaphores: []vulkan.VkSemaphore,
in_flight_fences: []vulkan.VkFence,

current_frame: usize = 0,

pub const max_frames_in_flight: usize = 2;

pub fn init(allocator: std.mem.Allocator, system: *VulkanSystem, surface: vulkan.VkSurfaceKHR) VulkanError!Swapchain {
    const swapchain_settings = try query_swapchain_settings(
        allocator,
        system.physical_device,
        system.logical_device,
        surface,
    );

    const swapchain_info = try create_swapchain(allocator, swapchain_settings);
    const swapchain_image_views = try create_image_views(
        allocator,
        system.logical_device,
        swapchain_info.images,
        swapchain_info.image_format,
    );

    const sync_objects = try create_sync_objects(
        allocator,
        system.logical_device,
    );

    return .{
        .swapchain = swapchain_info.swapchain,
        .swapchain_images = swapchain_info.images,
        .swapchain_image_format = swapchain_info.image_format,
        .swapchain_extent = swapchain_info.extent,
        .swapchain_image_views = swapchain_image_views,

        .image_available_semaphores = sync_objects.image_available_semaphores,
        .render_finished_semaphores = sync_objects.render_finished_semaphores,
        .in_flight_fences = sync_objects.in_flight_fences,
    };
}

pub fn deinit(self: Swapchain, allocator: std.mem.Allocator, system: *VulkanSystem) void {
    var i: usize = 0;
    while (i < max_frames_in_flight) : (i += 1) {
        vulkan.vkDestroySemaphore(system.logical_device, self.image_available_semaphores[i], null);
        vulkan.vkDestroySemaphore(system.logical_device, self.render_finished_semaphores[i], null);
        vulkan.vkDestroyFence(system.logical_device, self.in_flight_fences[i], null);
    }
    allocator.free(self.image_available_semaphores);
    allocator.free(self.render_finished_semaphores);
    allocator.free(self.in_flight_fences);

    i = 0;
    while (i < self.swapchain_image_views.len) : (i += 1) {
        vulkan.vkDestroyImageView(system.logical_device, self.swapchain_image_views[i], null);
    }
    allocator.free(self.swapchain_image_views);
    allocator.free(self.swapchain_images);
    vulkan.vkDestroySwapchainKHR(system.logical_device, self.swapchain, null);
}

pub fn recreate_swapchain(
    self: *Swapchain,
    allocator: std.mem.Allocator,
    system: *VulkanSystem,
    swapchain_settings: SwapchainSettings,
    window: *glfw.GLFWwindow,
) VulkanError!void {
    var width: c_int = 0;
    var height: c_int = 0;
    glfw.glfwGetFramebufferSize(window, &width, &height);
    while (width == 0 or height == 0) {
        glfw.glfwGetFramebufferSize(window, &width, &height);
        glfw.glfwWaitEvents();
    }

    var result = vulkan.vkDeviceWaitIdle(system.logical_device);
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }

    // --- Cleanup.

    var i: usize = 0;
    while (i < self.swapchain_image_views.len) : (i += 1) {
        vulkan.vkDestroyImageView(system.logical_device, self.swapchain_image_views[i], null);
    }
    allocator.free(self.swapchain_image_views);
    allocator.free(self.swapchain_images);
    vulkan.vkDestroySwapchainKHR(system.logical_device, self.swapchain, null);

    // ---

    const swapchain_info = try create_swapchain(
        allocator,
        swapchain_settings,
    );
    const swapchain_image_views = try create_image_views(
        allocator,
        system.logical_device,
        swapchain_info.images,
        swapchain_info.image_format,
    );

    self.swapchain = swapchain_info.swapchain;
    self.swapchain_images = swapchain_info.images;
    self.swapchain_image_format = swapchain_info.image_format;
    self.swapchain_extent = swapchain_info.extent;
    self.swapchain_image_views = swapchain_image_views;
}

const CreateSwapchainReturnType = struct {
    swapchain: vulkan.VkSwapchainKHR,
    images: []vulkan.VkImage,
    image_format: vulkan.VkFormat,
    extent: vulkan.VkExtent2D,
};

fn create_swapchain(
    allocator_: std.mem.Allocator,
    swapchain_settings: SwapchainSettings,
) VulkanError!CreateSwapchainReturnType {
    var create_info: vulkan.VkSwapchainCreateInfoKHR = .{
        .sType = vulkan.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = swapchain_settings.surface,
        .minImageCount = swapchain_settings.min_image_count,
        .imageFormat = swapchain_settings.surface_format.format,
        .imageColorSpace = swapchain_settings.surface_format.colorSpace,
        .imageExtent = swapchain_settings.extent,
        .imageArrayLayers = 1,
        .imageUsage = vulkan.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,

        .imageSharingMode = swapchain_settings.image_sharing_mode,
        .queueFamilyIndexCount = swapchain_settings.queue_family_index_count,
        .pQueueFamilyIndices = swapchain_settings.queue_family_indices[0..].ptr,
        .preTransform = swapchain_settings.capabilities.currentTransform,
        .compositeAlpha = vulkan.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = swapchain_settings.present_mode,
        .clipped = vulkan.VK_TRUE,
        .oldSwapchain = @ptrCast(vulkan.VK_NULL_HANDLE),
        .pNext = null,
        .flags = 0,
    };

    var swapchain: vulkan.VkSwapchainKHR = undefined;
    var result = vulkan.vkCreateSwapchainKHR(swapchain_settings.logical_device, &create_info, null, &swapchain);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            vulkan.VK_ERROR_DEVICE_LOST => return VulkanError.vk_error_device_lost,
            vulkan.VK_ERROR_SURFACE_LOST_KHR => return VulkanError.vk_error_surface_lost_khr,
            vulkan.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => return VulkanError.vk_error_native_window_in_use_khr,
            vulkan.VK_ERROR_INITIALIZATION_FAILED => return VulkanError.vk_error_initialization_failed,
            vulkan.VK_ERROR_COMPRESSION_EXHAUSTED_EXT => return VulkanError.vk_error_compression_exhausted_ext,
            else => unreachable,
        }
    }

    var image_count = swapchain_settings.min_image_count;
    result = vulkan.vkGetSwapchainImagesKHR(swapchain_settings.logical_device, swapchain, &image_count, null);
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }
    var swapchain_images = try allocator_.alloc(vulkan.VkImage, image_count);
    result = vulkan.vkGetSwapchainImagesKHR(swapchain_settings.logical_device, swapchain, &image_count, swapchain_images.ptr);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            else => unreachable,
        }
    }

    return .{
        .swapchain = swapchain,
        .images = swapchain_images,
        .image_format = swapchain_settings.surface_format.format,
        .extent = swapchain_settings.extent,
    };
}

fn create_image_views(
    allocator: std.mem.Allocator,
    logical_device: vulkan.VkDevice,
    images: []vulkan.VkImage,
    image_format: vulkan.VkFormat,
) VulkanError![]vulkan.VkImageView {
    var image_views = try allocator.alloc(vulkan.VkImageView, images.len);
    errdefer allocator.free(image_views);

    var i: usize = 0;
    var create_info: vulkan.VkImageViewCreateInfo = undefined;
    while (i < images.len) : (i += 1) {
        create_info = .{
            .sType = vulkan.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = images[i],
            .viewType = vulkan.VK_IMAGE_VIEW_TYPE_2D,
            .format = image_format,
            .components = .{
                .r = vulkan.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = vulkan.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = vulkan.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = vulkan.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask = vulkan.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .pNext = null,
            .flags = 0,
        };

        var result = vulkan.vkCreateImageView(logical_device, &create_info, null, &image_views[i]);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                vulkan.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS_KHR => return VulkanError.vk_error_invalid_opaque_capture_address_khr,
                else => unreachable,
            }
        }
    }

    return image_views;
}

const CreateSyncObjectsReturnType = struct {
    image_available_semaphores: []vulkan.VkSemaphore,
    render_finished_semaphores: []vulkan.VkSemaphore,
    in_flight_fences: []vulkan.VkFence,
};

fn create_sync_objects(allocator_: std.mem.Allocator, device: vulkan.VkDevice) VulkanError!CreateSyncObjectsReturnType {
    var image_available_semaphores = try allocator_.alloc(vulkan.VkSemaphore, max_frames_in_flight);
    errdefer allocator_.free(image_available_semaphores);
    var render_finished_semaphores = try allocator_.alloc(vulkan.VkSemaphore, max_frames_in_flight);
    errdefer allocator_.free(render_finished_semaphores);
    var in_flight_fences = try allocator_.alloc(vulkan.VkFence, max_frames_in_flight);
    errdefer allocator_.free(in_flight_fences);

    var semaphore_info = vulkan.VkSemaphoreCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
    };

    var fence_info = vulkan.VkFenceCreateInfo{
        .sType = vulkan.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .pNext = null,
        .flags = vulkan.VK_FENCE_CREATE_SIGNALED_BIT,
    };

    var i: usize = 0;
    while (i < max_frames_in_flight) : (i += 1) {
        var result = vulkan.vkCreateSemaphore(device, &semaphore_info, null, &image_available_semaphores[i]);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }
        errdefer vulkan.vkDestroySemaphore(device, image_available_semaphores[i], null);

        result = vulkan.vkCreateSemaphore(device, &semaphore_info, null, &render_finished_semaphores[i]);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }
        errdefer vulkan.vkDestroySemaphore(device, render_finished_semaphores[i], null);

        result = vulkan.vkCreateFence(device, &fence_info, null, &in_flight_fences[i]);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                else => unreachable,
            }
        }
    }

    return .{
        .image_available_semaphores = image_available_semaphores,
        .render_finished_semaphores = render_finished_semaphores,
        .in_flight_fences = in_flight_fences,
    };
}
