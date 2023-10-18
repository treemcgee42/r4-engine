const std = @import("std");
const vulkan = @import("vulkan");

// ---

pub const VkSurfaceKHR = vulkan.VkSurfaceKHR;

pub const VkExtent3D = vulkan.VkExtent3D;

// ---

pub const VkLayerProperties = vulkan.VkLayerProperties;
pub const VK_MAX_EXTENSION_NAME_SIZE = vulkan.VK_MAX_EXTENSION_NAME_SIZE;

pub const vkEnumerateInstanceLayerPropertiesError = error{
    VK_INCOMPLETE,
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,

    OutOfMemory,
};

pub fn vkEnumerateInstanceLayerProperties(
    allocator: std.mem.Allocator,
) vkEnumerateInstanceLayerPropertiesError![]VkLayerProperties {
    var available_layers_count: u32 = 0;
    var result = vulkan.vkEnumerateInstanceLayerProperties(
        &available_layers_count,
        null,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_INCOMPLETE => return vkEnumerateInstanceLayerPropertiesError.VK_INCOMPLETE,
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkEnumerateInstanceLayerPropertiesError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkEnumerateInstanceLayerPropertiesError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            else => unreachable,
        }
    }

    var available_layers = try allocator.alloc(
        vulkan.VkLayerProperties,
        available_layers_count,
    );
    errdefer allocator.free(available_layers);
    result = vulkan.vkEnumerateInstanceLayerProperties(
        &available_layers_count,
        available_layers.ptr,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_INCOMPLETE => return vkEnumerateInstanceLayerPropertiesError.VK_INCOMPLETE,
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkEnumerateInstanceLayerPropertiesError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkEnumerateInstanceLayerPropertiesError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            else => unreachable,
        }
    }

    return available_layers;
}

// ---

pub const VkApplicationInfo = struct {
    pApplicationName: [*c]const u8,
    applicationVersion: struct {
        major: u32,
        minor: u32,
        patch: u32,
    },

    pEngineName: [*c]const u8,
    engineVersion: struct {
        major: u32,
        minor: u32,
        patch: u32,
    },

    apiVersion: u32 = vulkan.VK_API_VERSION_1_0,

    pNext: ?*const anyopaque = null,

    fn to_vulkan_ty(self: *const VkApplicationInfo) vulkan.VkApplicationInfo {
        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = self.pApplicationName,
            .applicationVersion = vulkan.VK_MAKE_VERSION(
                self.applicationVersion.major,
                self.applicationVersion.minor,
                self.applicationVersion.patch,
            ),
            .pEngineName = self.pEngineName,
            .engineVersion = vulkan.VK_MAKE_VERSION(
                self.engineVersion.major,
                self.engineVersion.minor,
                self.engineVersion.patch,
            ),
            .apiVersion = self.apiVersion,
            .pNext = self.pNext,
        };
    }
};

pub const ExtensionNames = struct {
    pub const VK_EXT_DEBUG_UTILS = vulkan.VK_EXT_DEBUG_UTILS_EXTENSION_NAME;
    pub const VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2 = vulkan.VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME;
    pub const VK_KHR_PORTABILITY_ENUMERATION = vulkan.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME;
};

pub const VkInstanceCreateFlags = packed struct(u32) {
    enumerate_portability_khr: bool = false,

    _: u31 = 0,
};

pub const VkInstanceCreateInfo = struct {
    flags: VkInstanceCreateFlags = .{},

    pApplicationInfo: *const VkApplicationInfo,
    enabledLayerNames: []const [*c]const u8,
    enabledExtensionNames: []const [*c]const u8,

    pNext: ?*const anyopaque = null,

    fn to_vulkan_ty(self: *const VkInstanceCreateInfo, pApplicationInfo: *vulkan.VkApplicationInfo) vulkan.VkInstanceCreateInfo {
        pApplicationInfo.* = self.pApplicationInfo.to_vulkan_ty();

        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .flags = @bitCast(self.flags),
            .pApplicationInfo = pApplicationInfo,
            .enabledExtensionCount = @intCast(self.enabledExtensionNames.len),
            .ppEnabledExtensionNames = @ptrCast(self.enabledExtensionNames.ptr),
            .enabledLayerCount = @intCast(self.enabledLayerNames.len),
            .ppEnabledLayerNames = @ptrCast(self.enabledLayerNames.ptr),
            .pNext = self.pNext,
        };
    }
};

pub const VkAllocationCallbacks = vulkan.VkAllocationCallbacks; // GENERAL

pub const VkInstance = vulkan.VkInstance;

pub const vkCreateInstanceError = error{
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
    VK_ERROR_INITIALIZATION_FAILED,
    VK_ERROR_LAYER_NOT_PRESENT,
    VK_ERROR_EXTENSION_NOT_PRESENT,
    VK_ERROR_INCOMPATIBLE_DRIVER,
};

pub fn vkCreateInstance(
    pCreateInfo: *const VkInstanceCreateInfo,
    pAllocator: ?*const VkAllocationCallbacks,
) !VkInstance {
    var pApplicationInfo: vulkan.VkApplicationInfo = undefined;
    const create_info = pCreateInfo.to_vulkan_ty(&pApplicationInfo);

    var instance: vulkan.VkInstance = undefined;
    const result = vulkan.vkCreateInstance(
        &create_info,
        pAllocator,
        &instance,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkCreateInstanceError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkCreateInstanceError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_INITIALIZATION_FAILED => return vkCreateInstanceError.VK_ERROR_INITIALIZATION_FAILED,
            vulkan.VK_ERROR_LAYER_NOT_PRESENT => return vkCreateInstanceError.VK_ERROR_LAYER_NOT_PRESENT,
            vulkan.VK_ERROR_EXTENSION_NOT_PRESENT => return vkCreateInstanceError.VK_ERROR_EXTENSION_NOT_PRESENT,
            vulkan.VK_ERROR_INCOMPATIBLE_DRIVER => return vkCreateInstanceError.VK_ERROR_INCOMPATIBLE_DRIVER,
            else => unreachable,
        }
    }

    return instance;
}

// ---

pub const VkExtensionProperties = vulkan.VkExtensionProperties;

pub const vkEnumerateInstanceExtensionPropertiesError = error{
    VK_INCOMPLETE,
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
    VK_ERROR_LAYER_NOT_PRESENT,

    OutOfMemory,
};

pub fn vkEnumerateInstanceExtensionProperties(
    allocator: std.mem.Allocator,
) vkEnumerateInstanceExtensionPropertiesError![]VkExtensionProperties {
    var available_extensions_count: u32 = 0;
    var result = vulkan.vkEnumerateInstanceExtensionProperties(
        null,
        &available_extensions_count,
        null,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_INCOMPLETE => return vkEnumerateInstanceExtensionPropertiesError.VK_INCOMPLETE,
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkEnumerateInstanceExtensionPropertiesError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkEnumerateInstanceExtensionPropertiesError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_LAYER_NOT_PRESENT => return vkEnumerateInstanceExtensionPropertiesError.VK_ERROR_LAYER_NOT_PRESENT,
            else => unreachable,
        }
    }

    var available_extensions = try allocator.alloc(vulkan.VkExtensionProperties, available_extensions_count);
    result = vulkan.vkEnumerateInstanceExtensionProperties(
        null,
        &available_extensions_count,
        available_extensions.ptr,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_INCOMPLETE => return vkEnumerateInstanceExtensionPropertiesError.VK_INCOMPLETE,
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkEnumerateInstanceExtensionPropertiesError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkEnumerateInstanceExtensionPropertiesError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_LAYER_NOT_PRESENT => return vkEnumerateInstanceExtensionPropertiesError.VK_ERROR_LAYER_NOT_PRESENT,
            else => unreachable,
        }
    }

    return available_extensions;
}

// ---

pub const VkPhysicalDevice = vulkan.VkPhysicalDevice;

pub const vkEnumeratePhysicalDevicesError = error{
    VK_INCOMPLETE,
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
    VK_ERROR_INITIALIZATION_FAILED,

    OutOfMemory,
};

pub fn vkEnumeratePhysicalDevices(
    allocator_: std.mem.Allocator,
    instance: VkInstance,
) vkEnumeratePhysicalDevicesError![]VkPhysicalDevice {
    var device_count: u32 = 0;
    var result = vulkan.vkEnumeratePhysicalDevices(instance, &device_count, null);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_INCOMPLETE => return vkEnumeratePhysicalDevicesError.VK_INCOMPLETE,
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkEnumeratePhysicalDevicesError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkEnumeratePhysicalDevicesError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_INITIALIZATION_FAILED => return vkEnumeratePhysicalDevicesError.VK_ERROR_INITIALIZATION_FAILED,
            else => unreachable,
        }
    }

    var devices = try allocator_.alloc(vulkan.VkPhysicalDevice, device_count);
    result = vulkan.vkEnumeratePhysicalDevices(instance, &device_count, devices.ptr);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_INCOMPLETE => return vkEnumeratePhysicalDevicesError.VK_INCOMPLETE,
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkEnumeratePhysicalDevicesError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkEnumeratePhysicalDevicesError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_INITIALIZATION_FAILED => return vkEnumeratePhysicalDevicesError.VK_ERROR_INITIALIZATION_FAILED,
            else => unreachable,
        }
    }

    return devices;
}

pub const VkPhysicalDeviceProperties = vulkan.VkPhysicalDeviceProperties;

pub fn vkGetPhysicalDeviceProperties(
    device: VkPhysicalDevice,
) VkPhysicalDeviceProperties {
    var device_properties: vulkan.VkPhysicalDeviceProperties = undefined;
    vulkan.vkGetPhysicalDeviceProperties(device, &device_properties);

    return device_properties;
}

// ---

pub const VkQueueFlags = packed struct(u32) {
    graphics: bool = false,
    compute: bool = false,
    transfer: bool = false,
    sparse_binding: bool = false,

    // Provided by VK_VERSION_1_1
    protected: bool = false,
    // Provided by VK_KHR_video_decode_queue
    video_decode: bool = false,
    _: u2 = 0,

    // Provided by VK_NV_optical_flow
    optical_flow: bool = false,
    _a: u3 = 0,

    _b: u20 = 0,

    fn to_vulkan_ty(self: VkQueueFlags) vulkan.VkQueueFlags {
        return @bitCast(self);
    }
};

pub const VkQueueFamilyProperties = struct {
    queueFlags: VkQueueFlags = .{},
    queueCount: u32 = 0,
    timestampValidBits: u32 = 0,
    minImageTransferGranularity: VkExtent3D = .{ .width = 0, .height = 0, .depth = 0 },

    fn to_vulkan_ty(self: VkQueueFamilyProperties) vulkan.VkQueueFamilyProperties {
        return .{
            .queueFlags = self.queueFlags.to_vulkan_ty(),
            .queueCount = self.queueCount,
            .timestampValidBits = self.timestampValidBits,
            .minImageTransferGranularity = self.minImageTransferGranularity,
        };
    }

    fn from_vulkan_ty(queue_family_properties: vulkan.VkQueueFamilyProperties) VkQueueFamilyProperties {
        return .{
            .queueFlags = @bitCast(queue_family_properties.queueFlags),
            .queueCount = queue_family_properties.queueCount,
            .timestampValidBits = queue_family_properties.timestampValidBits,
            .minImageTransferGranularity = queue_family_properties.minImageTransferGranularity,
        };
    }
};

pub const vkGetPhysicalDeviceQueueFamilyPropertiesError = error{
    OutOfMemory,
};

pub fn vkGetPhysicalDeviceQueueFamilyProperties(
    allocator: std.mem.Allocator,
    physical_device: VkPhysicalDevice,
) vkGetPhysicalDeviceQueueFamilyPropertiesError![]VkQueueFamilyProperties {
    var queue_family_count: u32 = 0;
    vulkan.vkGetPhysicalDeviceQueueFamilyProperties(
        physical_device,
        &queue_family_count,
        null,
    );

    var vulkan_queue_families = try allocator.alloc(vulkan.VkQueueFamilyProperties, queue_family_count);
    defer allocator.free(vulkan_queue_families);
    vulkan.vkGetPhysicalDeviceQueueFamilyProperties(
        physical_device,
        &queue_family_count,
        vulkan_queue_families.ptr,
    );

    var queue_families = try allocator.alloc(VkQueueFamilyProperties, queue_family_count);
    var i: usize = 0;
    while (i < queue_families.len) : (i += 1) {
        queue_families[i] = VkQueueFamilyProperties.from_vulkan_ty(vulkan_queue_families[i]);
    }

    return queue_families;
}

// ---

pub const vkGetPhysicalDeviceSurfaceSupportKHRError = error{
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
    VK_ERROR_SURFACE_LOST_KHR,
};

pub fn vkGetPhysicalDeviceSurfaceSupportKHR(
    physicalDevice: VkPhysicalDevice,
    queueFamilyIndex: u32,
    surface: VkSurfaceKHR,
) vkGetPhysicalDeviceSurfaceSupportKHRError!bool {
    var present_support = vulkan.VK_FALSE;
    const result = vulkan.vkGetPhysicalDeviceSurfaceSupportKHR(
        physicalDevice,
        queueFamilyIndex,
        surface,
        &present_support,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkGetPhysicalDeviceSurfaceSupportKHRError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkGetPhysicalDeviceSurfaceSupportKHRError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_SURFACE_LOST_KHR => return vkGetPhysicalDeviceSurfaceSupportKHRError.VK_ERROR_SURFACE_LOST_KHR,
            else => unreachable,
        }
    }

    return present_support == vulkan.VK_TRUE;
}
