const std = @import("std");
const vulkan = @import("vulkan");
const l0vk = @import("./vulkan.zig");

pub const VkSurfaceKHR = vulkan.VkSurfaceKHR;

pub inline fn vkDestroySurfaceKHR(
    instance: l0vk.VkInstance,
    surface: VkSurfaceKHR,
    pAllocator: ?*const l0vk.VkAllocationCallbacks,
) void {
    vulkan.vkDestroySurfaceKHR(instance, surface, pAllocator);
}

pub const VkSurfaceTransformFlagsKHR = packed struct(u32) {
    identity: bool = false,
    rotate_90: bool = false,
    rotate_180: bool = false,
    rotate_270: bool = false,

    horizontal_mirror: bool = false,
    horizontal_mirror_rotate_90: bool = false,
    horizontal_mirror_rotate_180: bool = false,
    horizontal_mirror_rotate_270: bool = false,

    inherit: bool = false,
    _: u3 = 0,

    _a: u20 = 0,

    pub const Bits = enum(c_uint) {
        identity = 0x00000001,
        rotate_90 = 0x00000002,
        rotate_180 = 0x00000004,
        rotate_270 = 0x00000008,
        horizontal_mirror = 0x00000010,
        horizontal_mirror_rotate_90 = 0x00000020,
        horizontal_mirror_rotate_180 = 0x00000040,
        horizontal_mirror_rotate_270 = 0x00000080,
        inherit = 0x00000100,
    };
};

pub const VkCompositeAlphaFlagsKHR = packed struct(u32) {
    opaque_: bool = false,
    pre_multiplied: bool = false,
    post_multiplied: bool = false,
    inherit: bool = false,

    _: u28 = 0,

    pub const Bits = enum(c_uint) {
        opaque_ = 0x00000001,
        pre_multiplied = 0x00000002,
        post_multiplied = 0x00000004,
        inherit = 0x00000008,
    };
};

pub const VkSurfaceCapabilitiesKHR = struct {
    minImageCount: u32 = 0,
    maxImageCount: u32 = 0,
    currentExtent: l0vk.VkExtent2D = .{ .width = 0, .height = 0 },
    minImageExtent: l0vk.VkExtent2D = .{ .width = 0, .height = 0 },
    maxImageExtent: l0vk.VkExtent2D = .{ .width = 0, .height = 0 },
    maxImageArrayLayers: u32 = 0,
    supportedTransforms: VkSurfaceTransformFlagsKHR = .{},
    currentTransform: VkSurfaceTransformFlagsKHR.Bits = .identity,
    supportedCompositeAlpha: VkCompositeAlphaFlagsKHR = .{},
    supportedUsageFlags: l0vk.VkImageUsageFlags = .{},

    pub fn from_vulkan_ty(capabilities: vulkan.VkSurfaceCapabilitiesKHR) VkSurfaceCapabilitiesKHR {
        return .{
            .minImageCount = capabilities.minImageCount,
            .maxImageCount = capabilities.maxImageCount,
            .currentExtent = capabilities.currentExtent,
            .minImageExtent = capabilities.minImageExtent,
            .maxImageExtent = capabilities.maxImageExtent,
            .maxImageArrayLayers = capabilities.maxImageArrayLayers,
            .supportedTransforms = @bitCast(capabilities.supportedTransforms),
            .currentTransform = @enumFromInt(capabilities.currentTransform),
            .supportedCompositeAlpha = @bitCast(capabilities.supportedCompositeAlpha),
            .supportedUsageFlags = @bitCast(capabilities.supportedUsageFlags),
        };
    }
};

pub const VkColorSpaceKHR = enum(c_uint) {
    srgb_nonlinear_khr = 0,

    // Provided by VK_EXT_swapchain_colorspace
    display_p3_nonlinear_ext = 1000104001,
    extended_srgb_linear_ext = 1000104002,
    display_p3_linear_ext = 1000104003,
    dci_p3_nonlinear_ext = 1000104004,
    bt709_linear_ext = 1000104005,
    bt709_nonlinear_ext = 1000104006,
    bt2020_linear_ext = 1000104007,
    hdr10_st2084_ext = 1000104008,
    dolbyvision_ext = 1000104009,
    hdr10_hlg_ext = 1000104010,
    adobergb_linear_ext = 1000104011,
    adobergb_nonlinear_ext = 1000104012,
    pass_through_ext = 1000104013,
    extended_srgb_nonlinear_ext = 1000104014,

    // Provided by VK_AMD_display_native_hdr
    display_native_amd = 1000213000,

    // VK_COLORSPACE_SRGB_NONLINEAR_KHR = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
    // Provided by VK_EXT_swapchain_colorspace
    // VK_COLOR_SPACE_DCI_P3_LINEAR_EXT = VK_COLOR_SPACE_DISPLAY_P3_LINEAR_EXT,
};

pub const VkSurfaceFormatKHR = struct {
    format: l0vk.VkFormat,
    colorSpace: VkColorSpaceKHR,

    pub fn from_vulkan_ty(surface_format: vulkan.VkSurfaceFormatKHR) VkSurfaceFormatKHR {
        return VkSurfaceFormatKHR{
            .format = @enumFromInt(surface_format.format),
            .colorSpace = @enumFromInt(surface_format.colorSpace),
        };
    }
};
