const std = @import("std");
const glfw = @import("glfw");
const VulkanError = @import("./VulkanSystem.zig").VulkanError;
const SwapchainSettings = @import("./VulkanSystem.zig").SwapchainSettings;
pub const query_swapchain_settings = @import("./VulkanSystem.zig").query_swapchain_settings;
const buffer = @import("./buffer.zig");
const RenderPass = @import("./RenderPass.zig");
const VulkanSystem = @import("./VulkanSystem.zig");
const SemaphoreHandle = VulkanSystem.SemaphoreHandle;
const FenceHandle = VulkanSystem.FenceHandle;
const l0vk = @import("../layer0/vulkan/vulkan.zig");

const Swapchain = @This();

swapchain: l0vk.VkSwapchainKHR,
swapchain_images: []l0vk.VkImage,
swapchain_image_format: l0vk.VkFormat,
swapchain_extent: l0vk.VkExtent2D,
swapchain_image_views: []l0vk.VkImageView,

image_available_semaphores: []SemaphoreHandle,
a_semaphores: []SemaphoreHandle,
b_semaphores: []SemaphoreHandle,
render_finished_semaphores: []SemaphoreHandle,
in_flight_fences: []FenceHandle,

a_command_buffers: []l0vk.VkCommandBuffer,
b_command_buffers: []l0vk.VkCommandBuffer,

current_frame: usize = 0,

pub const max_frames_in_flight: usize = 2;

pub fn init(allocator: std.mem.Allocator, system: *VulkanSystem, surface: l0vk.VkSurfaceKHR) !Swapchain {
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

    // --- Sync objects.

    const image_available_semaphores = try create_semaphores(system);
    const a_semaphores = try create_semaphores(system);
    const b_semaphores = try create_semaphores(system);
    const render_finished_semaphores = try create_semaphores(system);

    const in_flight_fences = try create_fences(system);

    // --- Command buffers.

    const a_command_buffers = try create_command_buffers(system);
    const b_command_buffers = try create_command_buffers(system);

    // ---

    return .{
        .swapchain = swapchain_info.swapchain,
        .swapchain_images = swapchain_info.images,
        .swapchain_image_format = swapchain_info.image_format,
        .swapchain_extent = swapchain_info.extent,
        .swapchain_image_views = swapchain_image_views,

        .image_available_semaphores = image_available_semaphores,
        .a_semaphores = a_semaphores,
        .b_semaphores = b_semaphores,
        .render_finished_semaphores = render_finished_semaphores,
        .in_flight_fences = in_flight_fences,

        .a_command_buffers = a_command_buffers,
        .b_command_buffers = b_command_buffers,
    };
}

pub fn deinit(self: Swapchain, allocator: std.mem.Allocator, system: *VulkanSystem) void {
    allocator.free(self.image_available_semaphores);
    allocator.free(self.a_semaphores);
    allocator.free(self.b_semaphores);
    allocator.free(self.render_finished_semaphores);

    allocator.free(self.in_flight_fences);

    allocator.free(self.a_command_buffers);
    allocator.free(self.b_command_buffers);

    var i: usize = 0;
    while (i < self.swapchain_image_views.len) : (i += 1) {
        l0vk.vkDestroyImageView(system.logical_device, self.swapchain_image_views[i], null);
    }
    allocator.free(self.swapchain_image_views);
    allocator.free(self.swapchain_images);
    l0vk.vkDestroySwapchainKHR(system.logical_device, self.swapchain, null);
}

pub const DeinitGenericCtx = struct {
    swapchain: *Swapchain,
    system: *VulkanSystem,
};

pub fn deinit_generic(untyped_ctx: *anyopaque) void {
    const ctx: *DeinitGenericCtx = @ptrCast(@alignCast(untyped_ctx));

    ctx.swapchain.deinit(ctx.system.allocator, ctx.system);
    ctx.system.allocator.destroy(ctx);
}

pub fn recreate_swapchain(
    self: *Swapchain,
    allocator: std.mem.Allocator,
    system: *VulkanSystem,
    swapchain_settings: SwapchainSettings,
    window: *glfw.GLFWwindow,
) !void {
    var width: c_int = 0;
    var height: c_int = 0;
    glfw.glfwGetFramebufferSize(window, &width, &height);
    while (width == 0 or height == 0) {
        glfw.glfwGetFramebufferSize(window, &width, &height);
        glfw.glfwWaitEvents();
    }

    try l0vk.vkDeviceWaitIdle(system.logical_device);

    // --- Cleanup.

    var i: usize = 0;
    while (i < self.swapchain_image_views.len) : (i += 1) {
        l0vk.vkDestroyImageView(system.logical_device, self.swapchain_image_views[i], null);
    }
    allocator.free(self.swapchain_image_views);
    allocator.free(self.swapchain_images);
    l0vk.vkDestroySwapchainKHR(system.logical_device, self.swapchain, null);

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
    swapchain: l0vk.VkSwapchainKHR,
    images: []l0vk.VkImage,
    image_format: l0vk.VkFormat,
    extent: l0vk.VkExtent2D,
};

fn create_swapchain(
    allocator_: std.mem.Allocator,
    swapchain_settings: SwapchainSettings,
) !CreateSwapchainReturnType {
    const ci = l0vk.VkSwapchainCreateInfoKHR{
        .surface = swapchain_settings.surface,

        .minImageCount = swapchain_settings.min_image_count,
        .imageFormat = swapchain_settings.surface_format.format,
        .imageColorSpace = swapchain_settings.surface_format.colorSpace,
        .imageExtent = swapchain_settings.extent,
        .imageArrayLayers = 1,
        .imageUsage = l0vk.VkImageUsageFlags{
            .color_attachment = true,
        },
        .imageSharingMode = swapchain_settings.image_sharing_mode,

        .queueFamilyIndices = swapchain_settings.queue_family_indices[0..],
        .preTransform = swapchain_settings.capabilities.currentTransform,
        .compositeAlpha = l0vk.VkCompositeAlphaFlagsKHR.Bits.opaque_,
        .presentMode = swapchain_settings.present_mode,
        .clipped = true,
    };

    const swapchain = try l0vk.vkCreateSwapchainKHR(
        swapchain_settings.logical_device,
        &ci,
        null,
    );

    const swapchain_images = try l0vk.vkGetSwapchainImagesKHR(
        allocator_,
        swapchain_settings.logical_device,
        swapchain,
    );

    return .{
        .swapchain = swapchain,
        .images = swapchain_images,
        .image_format = swapchain_settings.surface_format.format,
        .extent = swapchain_settings.extent,
    };
}

fn create_image_views(
    allocator: std.mem.Allocator,
    logical_device: l0vk.VkDevice,
    images: []l0vk.VkImage,
    image_format: l0vk.VkFormat,
) ![]l0vk.VkImageView {
    var image_views = try allocator.alloc(l0vk.VkImageView, images.len);
    errdefer allocator.free(image_views);

    var i: usize = 0;
    var create_info: l0vk.VkImageViewCreateInfo = undefined;
    while (i < images.len) : (i += 1) {
        create_info = l0vk.VkImageViewCreateInfo{
            .image = images[i],
            .viewType = .ty_2d,
            .format = image_format,
            .components = .{
                .r = .identity,
                .g = .identity,
                .b = .identity,
                .a = .identity,
            },
            .subresourceRange = .{
                .aspectMask = .{
                    .color = true,
                },
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        image_views[i] = try l0vk.vkCreateImageView(logical_device, &create_info, null);
    }

    return image_views;
}

fn create_semaphores(system: *VulkanSystem) ![]SemaphoreHandle {
    var semaphore_handles = try system.allocator.alloc(SemaphoreHandle, max_frames_in_flight);

    var i: usize = 0;
    while (i < max_frames_in_flight) : (i += 1) {
        const semaphore = try system.create_semaphore();
        semaphore_handles[i] = semaphore;
    }

    return semaphore_handles;
}

fn create_fences(system: *VulkanSystem) ![]FenceHandle {
    var fence_handles = try system.allocator.alloc(FenceHandle, max_frames_in_flight);

    var i: usize = 0;
    while (i < max_frames_in_flight) : (i += 1) {
        const fence = try system.create_fence();
        fence_handles[i] = fence;
    }

    return fence_handles;
}

fn create_command_buffers(system: *VulkanSystem) ![]l0vk.VkCommandBuffer {
    const alloc_info = l0vk.VkCommandBufferAllocateInfo{
        .commandPool = system.command_pool,
        .level = .primary,
        .commandBufferCount = @intCast(max_frames_in_flight),
    };

    const to_return = try l0vk.vkAllocateCommandBuffers(
        system.allocator,
        system.logical_device,
        &alloc_info,
    );

    return to_return;
}

// ---

pub fn current_image_available_semaphore(self: *const Swapchain) SemaphoreHandle {
    return self.image_available_semaphores[self.current_frame];
}

pub fn current_render_finished_semaphore(self: *const Swapchain) SemaphoreHandle {
    return self.render_finished_semaphores[self.current_frame];
}

pub fn current_in_flight_fence(self: *const Swapchain) FenceHandle {
    return self.in_flight_fences[self.current_frame];
}
