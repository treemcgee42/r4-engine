const std = @import("std");
const vulkan = @import("../c.zig").vulkan;
const glfw = @import("../c.zig").glfw;
const VulkanError = @import("./vulkan.zig").VulkanError;
const find_queue_families = @import("./vulkan.zig").find_queue_families;

allocator: std.mem.Allocator,

logical_device: vulkan.VkDevice,

swapchain: vulkan.VkSwapchainKHR,
swapchain_images: []vulkan.VkImage,
swapchain_image_format: vulkan.VkFormat,
swapchain_extent: vulkan.VkExtent2D,
swapchain_image_views: []vulkan.VkImageView,

const Swapchain = @This();

pub fn init(
    allocator_: std.mem.Allocator,
    physical_device: vulkan.VkPhysicalDevice,
    logical_device: vulkan.VkDevice,
    surface: vulkan.VkSurfaceKHR,
) VulkanError!Swapchain {
    const swapchain_info = try create_swapchain(allocator_, physical_device, logical_device, surface);
    const swapchain_image_views = try create_image_views(
        allocator_,
        logical_device,
        swapchain_info.images,
        swapchain_info.image_format,
    );

    return .{
        .allocator = allocator_,

        .logical_device = logical_device,

        .swapchain = swapchain_info.swapchain,
        .swapchain_images = swapchain_info.images,
        .swapchain_image_format = swapchain_info.image_format,
        .swapchain_extent = swapchain_info.extent,
        .swapchain_image_views = swapchain_image_views,
    };
}

pub fn deinit(self: Swapchain) void {
    var i: usize = 0;
    while (i < self.swapchain_image_views.len) : (i += 1) {
        vulkan.vkDestroyImageView(self.logical_device, self.swapchain_image_views[i], null);
    }
    self.allocator.free(self.swapchain_image_views);
    self.allocator.free(self.swapchain_images);
    vulkan.vkDestroySwapchainKHR(self.logical_device, self.swapchain, null);
}

pub const SwapchainSupportDetails = struct {
    capabilities: vulkan.VkSurfaceCapabilitiesKHR,
    formats: std.ArrayList(vulkan.VkSurfaceFormatKHR),
    present_modes: std.ArrayList(vulkan.VkPresentModeKHR),
};

pub fn query_swapchain_support(
    allocator_: std.mem.Allocator,
    physical_device: vulkan.VkPhysicalDevice,
    surface: vulkan.VkSurfaceKHR,
) VulkanError!SwapchainSupportDetails {
    var capabilities: vulkan.VkSurfaceCapabilitiesKHR = undefined;
    var formats = std.ArrayList(vulkan.VkSurfaceFormatKHR).init(allocator_);
    var present_modes = std.ArrayList(vulkan.VkPresentModeKHR).init(allocator_);

    var result = vulkan.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &capabilities);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
            vulkan.VK_ERROR_SURFACE_LOST_KHR => return VulkanError.vk_error_surface_lost_khr,
            else => unreachable,
        }
    }

    // --- Format modes.

    var format_count: u32 = undefined;
    result = vulkan.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, null);
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }
    if (format_count != 0) {
        try formats.resize(format_count);
        result = vulkan.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, formats.items.ptr);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                vulkan.VK_ERROR_SURFACE_LOST_KHR => return VulkanError.vk_error_surface_lost_khr,
                else => unreachable,
            }
        }
    }

    // --- Present modes.

    var present_mode_count: u32 = undefined;
    result = vulkan.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, null);
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }
    if (present_mode_count != 0) {
        try present_modes.resize(present_mode_count);
        result = vulkan.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, present_modes.items.ptr);
        if (result != vulkan.VK_SUCCESS) {
            switch (result) {
                vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return VulkanError.vk_error_out_of_host_memory,
                vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return VulkanError.vk_error_out_of_device_memory,
                vulkan.VK_ERROR_SURFACE_LOST_KHR => return VulkanError.vk_error_surface_lost_khr,
                else => unreachable,
            }
        }
    }

    return .{
        .capabilities = capabilities,
        .formats = formats,
        .present_modes = present_modes,
    };
}

const CreateSwapchainReturnType = struct {
    swapchain: vulkan.VkSwapchainKHR,
    images: []vulkan.VkImage,
    image_format: vulkan.VkFormat,
    extent: vulkan.VkExtent2D,
};

fn create_swapchain(allocator_: std.mem.Allocator, physcial_device: vulkan.VkPhysicalDevice, logical_device: vulkan.VkDevice, surface: vulkan.VkSurfaceKHR) VulkanError!CreateSwapchainReturnType {
    const swap_chain_support = try query_swapchain_support(allocator_, physcial_device, surface);
    defer swap_chain_support.formats.deinit();
    defer swap_chain_support.present_modes.deinit();

    const surface_format = choose_swap_surface_format(swap_chain_support.formats.items);
    const present_mode = choose_swap_chain_present_mode(swap_chain_support.present_modes.items);
    const extent = choose_swap_extent(swap_chain_support.capabilities);

    var image_count: u32 = swap_chain_support.capabilities.minImageCount + 1;
    if (swap_chain_support.capabilities.maxImageCount > 0 and
        image_count > swap_chain_support.capabilities.maxImageCount)
    {
        image_count = swap_chain_support.capabilities.maxImageCount;
    }

    var image_sharing_mode: vulkan.VkSharingMode = undefined;
    var queue_family_index_count: u32 = undefined;
    const indices = try find_queue_families(physcial_device, allocator_, surface);
    const queue_family_indices = [_]u32{ indices.graphics_family.?, indices.present_family.? };
    const p_queue_family_indices: [*c]const u32 = queue_family_indices[0..].ptr;
    if (indices.graphics_family != indices.present_family) {
        image_sharing_mode = vulkan.VK_SHARING_MODE_CONCURRENT;
        queue_family_index_count = 2;
    } else {
        image_sharing_mode = vulkan.VK_SHARING_MODE_EXCLUSIVE;
        queue_family_index_count = 0;
    }

    var create_info: vulkan.VkSwapchainCreateInfoKHR = .{
        .sType = vulkan.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface,
        .minImageCount = image_count,
        .imageFormat = surface_format.format,
        .imageColorSpace = surface_format.colorSpace,
        .imageExtent = extent,
        .imageArrayLayers = 1,
        .imageUsage = vulkan.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,

        .imageSharingMode = image_sharing_mode,
        .queueFamilyIndexCount = queue_family_index_count,
        .pQueueFamilyIndices = p_queue_family_indices,
        .preTransform = swap_chain_support.capabilities.currentTransform,
        .compositeAlpha = vulkan.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = present_mode,
        .clipped = vulkan.VK_TRUE,
        .oldSwapchain = @ptrCast(vulkan.VK_NULL_HANDLE),
        .pNext = null,
        .flags = 0,
    };

    var swapchain: vulkan.VkSwapchainKHR = undefined;
    var result = vulkan.vkCreateSwapchainKHR(logical_device, &create_info, null, &swapchain);
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

    result = vulkan.vkGetSwapchainImagesKHR(logical_device, swapchain, &image_count, null);
    if (result != vulkan.VK_SUCCESS) {
        unreachable;
    }
    var swapchain_images = try allocator_.alloc(vulkan.VkImage, image_count);
    result = vulkan.vkGetSwapchainImagesKHR(logical_device, swapchain, &image_count, swapchain_images.ptr);
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
        .image_format = surface_format.format,
        .extent = extent,
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

fn choose_swap_surface_format(available_formats: []const vulkan.VkSurfaceFormatKHR) vulkan.VkSurfaceFormatKHR {
    for (available_formats) |available_format| {
        if (available_format.format == vulkan.VK_FORMAT_B8G8R8A8_SRGB and available_format.colorSpace == vulkan.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return available_format;
        }
    }

    return available_formats[0];
}

fn choose_swap_chain_present_mode(available_present_modes: []const vulkan.VkPresentModeKHR) vulkan.VkPresentModeKHR {
    for (available_present_modes) |available_present_mode| {
        if (available_present_mode == vulkan.VK_PRESENT_MODE_MAILBOX_KHR) {
            return available_present_mode;
        }
    }

    return vulkan.VK_PRESENT_MODE_FIFO_KHR;
}

fn choose_swap_extent(capabilities: vulkan.VkSurfaceCapabilitiesKHR) vulkan.VkExtent2D {
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    } else {
        const width = @as(u32, @intCast(glfw.glfwGetVideoMode(glfw.glfwGetPrimaryMonitor()).*.width));
        const height = @as(u32, @intCast(glfw.glfwGetVideoMode(glfw.glfwGetPrimaryMonitor()).*.height));

        var actual_extent = vulkan.VkExtent2D{
            .width = width,
            .height = height,
        };

        actual_extent.width = std.math.clamp(
            actual_extent.width,
            capabilities.minImageExtent.width,
            capabilities.maxImageExtent.width,
        );
        actual_extent.height = std.math.clamp(
            actual_extent.height,
            capabilities.minImageExtent.height,
            capabilities.maxImageExtent.height,
        );

        return actual_extent;
    }
}
