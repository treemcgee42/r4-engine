const std = @import("std");
const vulkan = @import("vulkan");

fn derived_from_vulkan_ty(vulkan_ty_instance: anytype, comptime TargetType: type) TargetType {
    var to_return: TargetType = undefined;

    inline for (std.meta.fields(@TypeOf(vulkan_ty_instance))) |field| {
        if (field.type == u32 or
            field.type == i32 or
            field.type == f32 or
            field.type == usize or
            field.type == [2]u32 or
            field.type == [3]u32 or
            field.type == [2]f32 or
            field.type == [16]u8 or
            field.type == [256]u8 or
            field.type == vulkan.VkDeviceSize)
        {
            const TargetFieldType = @TypeOf(@field(to_return, field.name));
            if (TargetFieldType == bool) {
                @field(to_return, field.name) = @field(vulkan_ty_instance, field.name) != 0;
                continue;
            }

            @field(to_return, field.name) = @bitCast(@field(vulkan_ty_instance, field.name));
            continue;
        }

        const TargetFieldType = @TypeOf(@field(to_return, field.name));
        @field(to_return, field.name) = TargetFieldType.from_vulkan_ty(@field(vulkan_ty_instance, field.name));
    }

    return to_return;
}

fn derived_to_vulkan_ty(wrapper_ty_instance: anytype, comptime TargetType: type) TargetType {
    var to_return: TargetType = undefined;

    inline for (std.meta.fields(@TypeOf(wrapper_ty_instance))) |field| {
        switch (field.type) {
            bool => {
                @field(to_return, field.name) = @intFromBool(@field(wrapper_ty_instance, field.name));
            },
            else => unreachable,
        }
    }

    return to_return;
}

// ---

pub const VkSurfaceKHR = vulkan.VkSurfaceKHR;

pub const VkExtent2D = vulkan.VkExtent2D;
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

pub const VkSampleCountFlags = packed struct(u32) {
    bit_1: bool = false,
    bit_2: bool = false,
    bit_4: bool = false,
    bit_8: bool = false,

    bit_16: bool = false,
    bit_32: bool = false,
    bit_64: bool = false,
    _: i1 = 0,

    _a: i24 = 0,

    fn to_vulkan_ty(self: VkSampleCountFlags) vulkan.VkSampleCountFlags {
        return @bitCast(self);
    }
};

pub const VkSampleCountFlagBits = enum(c_uint) {
    VK_SAMPLE_COUNT_1_BIT = 1,
    VK_SAMPLE_COUNT_2_BIT = 2,
    VK_SAMPLE_COUNT_4_BIT = 4,
    VK_SAMPLE_COUNT_8_BIT = 8,
    VK_SAMPLE_COUNT_16_BIT = 16,
    VK_SAMPLE_COUNT_32_BIT = 32,
    VK_SAMPLE_COUNT_64_BIT = 64,
};

pub const VkDeviceSize = vulkan.VkDeviceSize;

pub const VkPhysicalDeviceLimits = struct {
    maxImageDimension1D: u32 = 0,
    maxImageDimension2D: u32 = 0,
    maxImageDimension3D: u32 = 0,
    maxImageDimensionCube: u32 = 0,
    maxImageArrayLayers: u32 = 0,
    maxTexelBufferElements: u32 = 0,
    maxUniformBufferRange: u32 = 0,
    maxStorageBufferRange: u32 = 0,
    maxPushConstantsSize: u32 = 0,
    maxMemoryAllocationCount: u32 = 0,
    maxSamplerAllocationCount: u32 = 0,
    bufferImageGranularity: VkDeviceSize = 0,
    sparseAddressSpaceSize: VkDeviceSize = 0,
    maxBoundDescriptorSets: u32 = 0,
    maxPerStageDescriptorSamplers: u32 = 0,
    maxPerStageDescriptorUniformBuffers: u32 = 0,
    maxPerStageDescriptorStorageBuffers: u32 = 0,
    maxPerStageDescriptorSampledImages: u32 = 0,
    maxPerStageDescriptorStorageImages: u32 = 0,
    maxPerStageDescriptorInputAttachments: u32 = 0,
    maxPerStageResources: u32 = 0,
    maxDescriptorSetSamplers: u32 = 0,
    maxDescriptorSetUniformBuffers: u32 = 0,
    maxDescriptorSetUniformBuffersDynamic: u32 = 0,
    maxDescriptorSetStorageBuffers: u32 = 0,
    maxDescriptorSetStorageBuffersDynamic: u32 = 0,
    maxDescriptorSetSampledImages: u32 = 0,
    maxDescriptorSetStorageImages: u32 = 0,
    maxDescriptorSetInputAttachments: u32 = 0,
    maxVertexInputAttributes: u32 = 0,
    maxVertexInputBindings: u32 = 0,
    maxVertexInputAttributeOffset: u32 = 0,
    maxVertexInputBindingStride: u32 = 0,
    maxVertexOutputComponents: u32 = 0,
    maxTessellationGenerationLevel: u32 = 0,
    maxTessellationPatchSize: u32 = 0,
    maxTessellationControlPerVertexInputComponents: u32 = 0,
    maxTessellationControlPerVertexOutputComponents: u32 = 0,
    maxTessellationControlPerPatchOutputComponents: u32 = 0,
    maxTessellationControlTotalOutputComponents: u32 = 0,
    maxTessellationEvaluationInputComponents: u32 = 0,
    maxTessellationEvaluationOutputComponents: u32 = 0,
    maxGeometryShaderInvocations: u32 = 0,
    maxGeometryInputComponents: u32 = 0,
    maxGeometryOutputComponents: u32 = 0,
    maxGeometryOutputVertices: u32 = 0,
    maxGeometryTotalOutputComponents: u32 = 0,
    maxFragmentInputComponents: u32 = 0,
    maxFragmentOutputAttachments: u32 = 0,
    maxFragmentDualSrcAttachments: u32 = 0,
    maxFragmentCombinedOutputResources: u32 = 0,
    maxComputeSharedMemorySize: u32 = 0,
    maxComputeWorkGroupCount: [3]u32 = [3]u32{ 0, 0, 0 },
    maxComputeWorkGroupInvocations: u32 = 0,
    maxComputeWorkGroupSize: [3]u32 = [3]u32{ 0, 0, 0 },
    subPixelPrecisionBits: u32 = 0,
    subTexelPrecisionBits: u32 = 0,
    mipmapPrecisionBits: u32 = 0,
    maxDrawIndexedIndexValue: u32 = 0,
    maxDrawIndirectCount: u32 = 0,
    maxSamplerLodBias: f32 = 0,
    maxSamplerAnisotropy: f32 = 0,
    maxViewports: u32 = 0,
    maxViewportDimensions: [2]u32 = [2]u32{ 0, 0 },
    viewportBoundsRange: [2]f32 = [2]f32{ 0, 0 },
    viewportSubPixelBits: u32 = 0,
    minMemoryMapAlignment: usize = 0,
    minTexelBufferOffsetAlignment: VkDeviceSize = 0,
    minUniformBufferOffsetAlignment: VkDeviceSize = 0,
    minStorageBufferOffsetAlignment: VkDeviceSize = 0,
    minTexelOffset: i32 = 0,
    maxTexelOffset: u32 = 0,
    minTexelGatherOffset: i32 = 0,
    maxTexelGatherOffset: u32 = 0,
    minInterpolationOffset: f32 = 0,
    maxInterpolationOffset: f32 = 0,
    subPixelInterpolationOffsetBits: u32 = 0,
    maxFramebufferWidth: u32 = 0,
    maxFramebufferHeight: u32 = 0,
    maxFramebufferLayers: u32 = 0,
    framebufferColorSampleCounts: VkSampleCountFlags = .{},
    framebufferDepthSampleCounts: VkSampleCountFlags = .{},
    framebufferStencilSampleCounts: VkSampleCountFlags = .{},
    framebufferNoAttachmentsSampleCounts: VkSampleCountFlags = .{},
    maxColorAttachments: u32 = 0,
    sampledImageColorSampleCounts: VkSampleCountFlags = .{},
    sampledImageIntegerSampleCounts: VkSampleCountFlags = .{},
    sampledImageDepthSampleCounts: VkSampleCountFlags = .{},
    sampledImageStencilSampleCounts: VkSampleCountFlags = .{},
    storageImageSampleCounts: VkSampleCountFlags = .{},
    maxSampleMaskWords: u32 = 0,
    timestampComputeAndGraphics: bool = false,
    timestampPeriod: f32 = 0,
    maxClipDistances: u32 = 0,
    maxCullDistances: u32 = 0,
    maxCombinedClipAndCullDistances: u32 = 0,
    discreteQueuePriorities: u32 = 0,
    pointSizeRange: [2]f32 = [2]f32{ 0, 0 },
    lineWidthRange: [2]f32 = [2]f32{ 0, 0 },
    pointSizeGranularity: f32 = 0,
    lineWidthGranularity: f32 = 0,
    strictLines: bool = false,
    standardSampleLocations: bool = false,
    optimalBufferCopyOffsetAlignment: VkDeviceSize = 0,
    optimalBufferCopyRowPitchAlignment: VkDeviceSize = 0,
    nonCoherentAtomSize: VkDeviceSize = 0,

    fn from_vulkan_ty(limits: vulkan.VkPhysicalDeviceLimits) VkPhysicalDeviceLimits {
        return derived_from_vulkan_ty(limits, VkPhysicalDeviceLimits);
    }
};

pub const VkPhysicalDeviceType = enum(c_uint) {
    other = 0,
    integrated_gpu = 1,
    discrete_gpu = 2,
    virtual_gpu = 3,
    cpu = 4,

    fn from_vulkan_ty(physical_device_type: vulkan.VkPhysicalDeviceType) VkPhysicalDeviceType {
        return @enumFromInt(physical_device_type);
    }
};

pub const VkPhysicalDeviceSparseProperties = struct {
    residencyStandard2DBlockShape: bool = false,
    residencyStandard2DMultisampleBlockShape: bool = false,
    residencyStandard3DBlockShape: bool = false,
    residencyAlignedMipSize: bool = false,
    residencyNonResidentStrict: bool = false,

    fn from_vulkan_ty(sparse_properties: vulkan.VkPhysicalDeviceSparseProperties) VkPhysicalDeviceSparseProperties {
        return .{
            .residencyStandard2DBlockShape = sparse_properties.residencyStandard2DBlockShape != 0,
            .residencyStandard2DMultisampleBlockShape = sparse_properties.residencyStandard2DMultisampleBlockShape != 0,
            .residencyStandard3DBlockShape = sparse_properties.residencyStandard3DBlockShape != 0,
            .residencyAlignedMipSize = sparse_properties.residencyAlignedMipSize != 0,
            .residencyNonResidentStrict = sparse_properties.residencyNonResidentStrict != 0,
        };
    }
};

pub const VkPhysicalDeviceProperties = struct {
    apiVersion: u32 = 0,
    driverVersion: u32 = 0,
    vendorID: u32 = 0,
    deviceID: u32 = 0,
    deviceType: VkPhysicalDeviceType = .other,
    deviceName: [256]u8 = std.mem.zeroes([256]u8),
    pipelineCacheUUID: [16]u8 = std.mem.zeroes([16]u8),
    limits: VkPhysicalDeviceLimits = .{},
    sparseProperties: VkPhysicalDeviceSparseProperties = .{},

    fn from_vulkan_ty(physical_device_properties: vulkan.VkPhysicalDeviceProperties) VkPhysicalDeviceProperties {
        return derived_from_vulkan_ty(
            physical_device_properties,
            VkPhysicalDeviceProperties,
        );
    }
};

pub fn vkGetPhysicalDeviceProperties(
    device: VkPhysicalDevice,
) VkPhysicalDeviceProperties {
    var device_properties: vulkan.VkPhysicalDeviceProperties = undefined;
    vulkan.vkGetPhysicalDeviceProperties(device, &device_properties);

    return VkPhysicalDeviceProperties.from_vulkan_ty(device_properties);
}

pub const VkPhysicalDeviceFeatures = struct {
    robustBufferAccess: bool = false,
    fullDrawIndexUint32: bool = false,
    imageCubeArray: bool = false,
    independentBlend: bool = false,
    geometryShader: bool = false,
    tessellationShader: bool = false,
    sampleRateShading: bool = false,
    dualSrcBlend: bool = false,
    logicOp: bool = false,
    multiDrawIndirect: bool = false,
    drawIndirectFirstInstance: bool = false,
    depthClamp: bool = false,
    depthBiasClamp: bool = false,
    fillModeNonSolid: bool = false,
    depthBounds: bool = false,
    wideLines: bool = false,
    largePoints: bool = false,
    alphaToOne: bool = false,
    multiViewport: bool = false,
    samplerAnisotropy: bool = false,
    textureCompressionETC2: bool = false,
    textureCompressionASTC_LDR: bool = false,
    textureCompressionBC: bool = false,
    occlusionQueryPrecise: bool = false,
    pipelineStatisticsQuery: bool = false,
    vertexPipelineStoresAndAtomics: bool = false,
    fragmentStoresAndAtomics: bool = false,
    shaderTessellationAndGeometryPointSize: bool = false,
    shaderImageGatherExtended: bool = false,
    shaderStorageImageExtendedFormats: bool = false,
    shaderStorageImageMultisample: bool = false,
    shaderStorageImageReadWithoutFormat: bool = false,
    shaderStorageImageWriteWithoutFormat: bool = false,
    shaderUniformBufferArrayDynamicIndexing: bool = false,
    shaderSampledImageArrayDynamicIndexing: bool = false,
    shaderStorageBufferArrayDynamicIndexing: bool = false,
    shaderStorageImageArrayDynamicIndexing: bool = false,
    shaderClipDistance: bool = false,
    shaderCullDistance: bool = false,
    shaderFloat64: bool = false,
    shaderInt64: bool = false,
    shaderInt16: bool = false,
    shaderResourceResidency: bool = false,
    shaderResourceMinLod: bool = false,
    sparseBinding: bool = false,
    sparseResidencyBuffer: bool = false,
    sparseResidencyImage2D: bool = false,
    sparseResidencyImage3D: bool = false,
    sparseResidency2Samples: bool = false,
    sparseResidency4Samples: bool = false,
    sparseResidency8Samples: bool = false,
    sparseResidency16Samples: bool = false,
    sparseResidencyAliased: bool = false,
    variableMultisampleRate: bool = false,
    inheritedQueries: bool = false,

    fn from_vulkan_ty(physical_device_features: vulkan.VkPhysicalDeviceFeatures) VkPhysicalDeviceFeatures {
        return derived_from_vulkan_ty(
            physical_device_features,
            VkPhysicalDeviceFeatures,
        );
    }

    fn to_vulkan_ty(self: VkPhysicalDeviceFeatures) vulkan.VkPhysicalDeviceFeatures {
        return derived_to_vulkan_ty(self, vulkan.VkPhysicalDeviceFeatures);
    }
};

pub fn vkGetPhysicalDeviceFeatures(
    device: VkPhysicalDevice,
) VkPhysicalDeviceFeatures {
    var supported_features: vulkan.VkPhysicalDeviceFeatures = undefined;
    vulkan.vkGetPhysicalDeviceFeatures(device, &supported_features);

    return VkPhysicalDeviceFeatures.from_vulkan_ty(supported_features);
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

pub const VkDeviceQueueCreateFlags = packed struct(u32) {
    // Provided by VK_VERSION_1_1
    protected: bool = false,
    _: u3 = 0,

    _a: u28 = 0,
};

pub const VkDeviceQueueCreateInfo = struct {
    flags: VkDeviceQueueCreateFlags = .{},
    queueFamilyIndex: u32 = 0,
    queueCount: u32 = 0,
    pQueuePriorities: [*c]const f32 = std.mem.zeroes([*c]const f32),

    pNext: ?*const anyopaque = null,

    fn to_vulkan_ty(self: VkDeviceQueueCreateInfo) vulkan.VkDeviceQueueCreateInfo {
        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = self.queueFamilyIndex,
            .queueCount = self.queueCount,
            .pQueuePriorities = self.pQueuePriorities,
            .pNext = self.pNext,
            .flags = @bitCast(self.flags),
        };
    }
};

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

// ---

pub const vkEnumerateDeviceExtensionPropertiesError = error{
    VK_INCOMPLETE,
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
    VK_ERROR_LAYER_NOT_PRESENT,

    OutOfMemory,
};

pub fn vkEnumerateDeviceExtensionProperties(
    allocator: std.mem.Allocator,
    physicalDevice: VkPhysicalDevice,
    pLayerName: [*c]const u8,
) vkEnumerateDeviceExtensionPropertiesError![]VkExtensionProperties {
    _ = pLayerName;
    var extension_count: u32 = 0;
    var result = vulkan.vkEnumerateDeviceExtensionProperties(
        physicalDevice,
        null,
        &extension_count,
        null,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_INCOMPLETE => return vkEnumerateDeviceExtensionPropertiesError.VK_INCOMPLETE,
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkEnumerateDeviceExtensionPropertiesError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkEnumerateDeviceExtensionPropertiesError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_LAYER_NOT_PRESENT => return vkEnumerateDeviceExtensionPropertiesError.VK_ERROR_LAYER_NOT_PRESENT,
            else => unreachable,
        }
    }

    var available_extensions = try allocator.alloc(vulkan.VkExtensionProperties, extension_count);
    result = vulkan.vkEnumerateDeviceExtensionProperties(
        physicalDevice,
        null,
        &extension_count,
        available_extensions.ptr,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_INCOMPLETE => return vkEnumerateDeviceExtensionPropertiesError.VK_INCOMPLETE,
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkEnumerateDeviceExtensionPropertiesError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkEnumerateDeviceExtensionPropertiesError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_LAYER_NOT_PRESENT => return vkEnumerateDeviceExtensionPropertiesError.VK_ERROR_LAYER_NOT_PRESENT,
            else => unreachable,
        }
    }

    return available_extensions;
}

// ---

pub const VkDeviceCreateInfo = struct {
    queueCreateInfos: []const VkDeviceQueueCreateInfo = &.{},

    enabledLayerNames: []const [*c]const u8 = &.{},
    enabledExtensionNames: []const [*c]const u8 = &.{},

    pEnabledFeatures: ?*const VkPhysicalDeviceFeatures = null,

    pNext: ?*const anyopaque = null,

    fn to_vulkan_ty(
        self: VkDeviceCreateInfo,
        pQueueCreateInfos: []vulkan.VkDeviceQueueCreateInfo,
        pEnabledFeatures: *vulkan.VkPhysicalDeviceFeatures,
    ) vulkan.VkDeviceCreateInfo {
        std.debug.assert(pQueueCreateInfos.len >= self.queueCreateInfos.len);
        var i: usize = 0;
        while (i < self.queueCreateInfos.len) : (i += 1) {
            pQueueCreateInfos[i] = self.queueCreateInfos[i].to_vulkan_ty();
        }

        var pEnabledFeaturesClone: ?*vulkan.VkPhysicalDeviceFeatures = null;
        if (self.pEnabledFeatures != null) {
            pEnabledFeatures.* = self.pEnabledFeatures.?.to_vulkan_ty();
            pEnabledFeaturesClone = pEnabledFeatures;
        }

        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .flags = 0,

            .queueCreateInfoCount = @intCast(self.queueCreateInfos.len),
            .pQueueCreateInfos = pQueueCreateInfos.ptr,

            .enabledLayerCount = @intCast(self.enabledLayerNames.len),
            .ppEnabledLayerNames = @ptrCast(self.enabledLayerNames.ptr),

            .enabledExtensionCount = @intCast(self.enabledExtensionNames.len),
            .ppEnabledExtensionNames = @ptrCast(self.enabledExtensionNames.ptr),

            .pEnabledFeatures = pEnabledFeaturesClone,

            .pNext = self.pNext,
        };
    }
};

pub const vkCreateDeviceError = error{
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
    VK_ERROR_INITIALIZATION_FAILED,
    VK_ERROR_EXTENSION_NOT_PRESENT,
    VK_ERROR_FEATURE_NOT_PRESENT,
    VK_ERROR_TOO_MANY_OBJECTS,
    VK_ERROR_DEVICE_LOST,
};

pub const VkDevice = vulkan.VkDevice;

pub fn vkCreateDevice(
    physicalDevice: VkPhysicalDevice,
    pCreateInfo: *const VkDeviceCreateInfo,
    pAllocator: ?*const VkAllocationCallbacks,
) vkCreateDeviceError!VkDevice {
    _ = pAllocator;

    var pQueueCreateInfos: [5]vulkan.VkDeviceQueueCreateInfo = undefined;
    var enabledFeatures: vulkan.VkPhysicalDeviceFeatures = undefined;
    const create_info = pCreateInfo.to_vulkan_ty(
        pQueueCreateInfos[0..],
        &enabledFeatures,
    );

    var logical_device: vulkan.VkDevice = undefined;
    const result = vulkan.vkCreateDevice(
        physicalDevice,
        &create_info,
        null,
        &logical_device,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkCreateDeviceError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkCreateDeviceError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_INITIALIZATION_FAILED => return vkCreateDeviceError.VK_ERROR_INITIALIZATION_FAILED,
            vulkan.VK_ERROR_EXTENSION_NOT_PRESENT => return vkCreateDeviceError.VK_ERROR_EXTENSION_NOT_PRESENT,
            vulkan.VK_ERROR_FEATURE_NOT_PRESENT => return vkCreateDeviceError.VK_ERROR_FEATURE_NOT_PRESENT,
            vulkan.VK_ERROR_TOO_MANY_OBJECTS => return vkCreateDeviceError.VK_ERROR_TOO_MANY_OBJECTS,
            vulkan.VK_ERROR_DEVICE_LOST => return vkCreateDeviceError.VK_ERROR_DEVICE_LOST,
            else => unreachable,
        }
    }

    return logical_device;
}

// ---

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

pub const VkImageUsageFlags = packed struct(u32) {
    transfer_src: bool = false,
    transfer_dst: bool = false,
    sampled: bool = false,
    storage: bool = false,

    color_attachment: bool = false,
    depth_stencil_attachment: bool = false,
    transient_attachment: bool = false,
    input_attachment: bool = false,

    fragment_shading_rate_attachment_khr: bool = false,
    fragment_density_map_ext: bool = false,
    video_decode_dst_khr: bool = false,
    video_decode_src_khr: bool = false,

    video_decode_dpb_khr: bool = false,
    video_encode_dst_khr: bool = false,
    video_encode_src_khr: bool = false,
    video_encode_dpb_khr: bool = false,

    invocation_mask_huawei: bool = false,
    attachment_feedback_loop_ext: bool = false,
    _: u2 = 0,

    sample_weight_bit_qcom: bool = false,
    sample_block_match_qcom: bool = false,
    host_transfer_ext: bool = false,
    _a: u1 = 0,

    _b: u8 = 0,

    pub const Bits = enum(c_uint) {
        transfer_src = 0x00000001,
        transfer_dst = 0x00000002,
        sampled = 0x00000004,
        storage = 0x00000008,

        color_attachment = 0x00000010,
        depth_stencil_attachment = 0x00000020,
        transient_attachment = 0x00000040,
        input_attachment = 0x00000080,

        fragment_shading_rate_attachment_khr = 0x00000100,
        fragment_density_map_ext = 0x00000200,
        video_decode_dst_khr = 0x00000400,
        video_decode_src_khr = 0x00000800,

        video_decode_dpb_khr = 0x00001000,
        video_encode_dst_khr = 0x00002000,
        video_encode_src_khr = 0x00004000,
        video_encode_dpb_khr = 0x00008000,

        invocation_mask_huawei = 0x00040000,
        attachment_feedback_loop_ext = 0x00080000,

        sample_weight_bit_qcom = 0x00100000,
        sample_block_match_qcom = 0x00200000,
        host_transfer_ext = 0x00400000,

        // Provided by VK_NV_shading_rate_image
        // VK_IMAGE_USAGE_SHADING_RATE_IMAGE_BIT_NV = VK_IMAGE_USAGE_FRAGMENT_SHADING_RATE_ATTACHMENT_BIT_KHR,
    };
};

pub const VkSurfaceCapabilitiesKHR = struct {
    minImageCount: u32 = 0,
    maxImageCount: u32 = 0,
    currentExtent: VkExtent2D = .{ .width = 0, .height = 0 },
    minImageExtent: VkExtent2D = .{ .width = 0, .height = 0 },
    maxImageExtent: VkExtent2D = .{ .width = 0, .height = 0 },
    maxImageArrayLayers: u32 = 0,
    supportedTransforms: VkSurfaceTransformFlagsKHR = .{},
    currentTransform: VkSurfaceTransformFlagsKHR.Bits = .identity,
    supportedCompositeAlpha: VkCompositeAlphaFlagsKHR = .{},
    supportedUsageFlags: VkImageUsageFlags = .{},

    fn from_vulkan_ty(capabilities: vulkan.VkSurfaceCapabilitiesKHR) VkSurfaceCapabilitiesKHR {
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

pub const vkGetPhysicalDeviceSurfaceCapabilitiesKHRError = error{
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
    VK_ERROR_SURFACE_LOST_KHR,
};

pub fn vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
    physicalDevice: VkPhysicalDevice,
    surface: VkSurfaceKHR,
) vkGetPhysicalDeviceSurfaceCapabilitiesKHRError!VkSurfaceCapabilitiesKHR {
    var capabilities: vulkan.VkSurfaceCapabilitiesKHR = undefined;
    const result = vulkan.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
        physicalDevice,
        surface,
        &capabilities,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkGetPhysicalDeviceSurfaceCapabilitiesKHRError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkGetPhysicalDeviceSurfaceCapabilitiesKHRError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_SURFACE_LOST_KHR => return vkGetPhysicalDeviceSurfaceCapabilitiesKHRError.VK_ERROR_SURFACE_LOST_KHR,
            else => unreachable,
        }
    }

    return VkSurfaceCapabilitiesKHR.from_vulkan_ty(capabilities);
}
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

pub const VkFormat = enum(c_uint) {
    undefined = 0,

    r4g4_unorm_pack8 = 1,

    r4g4b4a4_unorm_pack16 = 2,
    b4g4r4a4_unorm_pack16 = 3,

    r5g6b5_unorm_pack16 = 4,
    b5g6r5_unorm_pack16 = 5,

    r5g5b5a1_unorm_pack16 = 6,
    b5g5r5a1_unorm_pack16 = 7,
    a1r5g5b5_unorm_pack16 = 8,

    r8_unorm = 9,
    r8_snorm = 10,
    r8_uscaled = 11,
    r8_sscaled = 12,
    r8_uint = 13,
    r8_sint = 14,
    r8_srgb = 15,

    r8g8_unorm = 16,
    r8g8_snorm = 17,
    r8g8_uscaled = 18,
    r8g8_sscaled = 19,
    r8g8_uint = 20,
    r8g8_sint = 21,
    r8g8_srgb = 22,

    r8g8b8_unorm = 23,
    r8g8b8_snorm = 24,
    r8g8b8_uscaled = 25,
    r8g8b8_sscaled = 26,
    r8g8b8_uint = 27,
    r8g8b8_sint = 28,
    r8g8b8_srgb = 29,

    b8g8r8_unorm = 30,
    b8g8r8_snorm = 31,
    b8g8r8_uscaled = 32,
    b8g8r8_sscaled = 33,
    b8g8r8_uint = 34,
    b8g8r8_sint = 35,
    b8g8r8_srgb = 36,

    r8g8b8a8_unorm = 37,
    r8g8b8a8_snorm = 38,
    r8g8b8a8_uscaled = 39,
    r8g8b8a8_sscaled = 40,
    r8g8b8a8_uint = 41,
    r8g8b8a8_sint = 42,
    r8g8b8a8_srgb = 43,

    b8g8r8a8_unorm = 44,
    b8g8r8a8_snorm = 45,
    b8g8r8a8_uscaled = 46,
    b8g8r8a8_sscaled = 47,
    b8g8r8a8_uint = 48,
    b8g8r8a8_sint = 49,
    b8g8r8a8_srgb = 50,

    a8b8g8r8_unorm_pack32 = 51,
    a8b8g8r8_snorm_pack32 = 52,
    a8b8g8r8_uscaled_pack32 = 53,
    a8b8g8r8_sscaled_pack32 = 54,
    a8b8g8r8_uint_pack32 = 55,
    a8b8g8r8_sint_pack32 = 56,
    a8b8g8r8_srgb_pack32 = 57,

    a2r10g10b10_unorm_pack32 = 58,
    a2r10g10b10_snorm_pack32 = 59,
    a2r10g10b10_uscaled_pack32 = 60,
    a2r10g10b10_sscaled_pack32 = 61,
    a2r10g10b10_uint_pack32 = 62,
    a2r10g10b10_sint_pack32 = 63,
    a2b10g10r10_unorm_pack32 = 64,
    a2b10g10r10_snorm_pack32 = 65,
    a2b10g10r10_uscaled_pack32 = 66,
    a2b10g10r10_sscaled_pack32 = 67,
    a2b10g10r10_uint_pack32 = 68,
    a2b10g10r10_sint_pack32 = 69,

    r16_unorm = 70,
    r16_snorm = 71,
    r16_uscaled = 72,
    r16_sscaled = 73,
    r16_uint = 74,
    r16_sint = 75,
    r16_sfloat = 76,

    r16g16_unorm = 77,
    r16g16_snorm = 78,
    r16g16_uscaled = 79,
    r16g16_sscaled = 80,
    r16g16_uint = 81,
    r16g16_sint = 82,
    r16g16_sfloat = 83,

    r16g16b16_unorm = 84,
    r16g16b16_snorm = 85,
    r16g16b16_uscaled = 86,
    r16g16b16_sscaled = 87,
    r16g16b16_uint = 88,
    r16g16b16_sint = 89,
    r16g16b16_sfloat = 90,

    r16g16b16a16_unorm = 91,
    r16g16b16a16_snorm = 92,
    r16g16b16a16_uscaled = 93,
    r16g16b16a16_sscaled = 94,
    r16g16b16a16_uint = 95,
    r16g16b16a16_sint = 96,
    r16g16b16a16_sfloat = 97,

    r32_uint = 98,
    r32_sint = 99,
    r32_sfloat = 100,

    r32g32_uint = 101,
    r32g32_sint = 102,
    r32g32_sfloat = 103,

    r32g32b32_uint = 104,
    r32g32b32_sint = 105,
    r32g32b32_sfloat = 106,

    r32g32b32a32_uint = 107,
    r32g32b32a32_sint = 108,
    r32g32b32a32_sfloat = 109,

    r64_uint = 110,
    r64_sint = 111,
    r64_sfloat = 112,

    r64g64_uint = 113,
    r64g64_sint = 114,
    r64g64_sfloat = 115,

    r64g64b64_uint = 116,
    r64g64b64_sint = 117,
    r64g64b64_sfloat = 118,

    r64g64b64a64_uint = 119,
    r64g64b64a64_sint = 120,
    r64g64b64a64_sfloat = 121,

    b10g11r11_ufloat_pack32 = 122,

    e5b9g9r9_ufloat_pack32 = 123,

    d16_unorm = 124,

    x8_d24_unorm_pack32 = 125,

    d32_sfloat = 126,

    s8_uint = 127,

    d16_unorm_s8_uint = 128,

    d24_unorm_s8_uint = 129,

    d32_sfloat_s8_uint = 130,

    bc1_rgb_unorm_block = 131,
    bc1_rgb_srgb_block = 132,

    bc1_rgba_unorm_block = 133,
    bc1_rgba_srgb_block = 134,

    bc2_unorm_block = 135,
    bc2_srgb_block = 136,

    bc3_unorm_block = 137,
    bc3_srgb_block = 138,

    bc4_unorm_block = 139,
    bc4_snorm_block = 140,

    bc5_unorm_block = 141,
    bc5_snorm_block = 142,

    bc6h_ufloat_block = 143,
    bc6h_sfloat_block = 144,

    bc7_unorm_block = 145,
    bc7_srgb_block = 146,

    etc2_r8g8b8_unorm_block = 147,
    etc2_r8g8b8_srgb_block = 148,

    etc2_r8g8b8a1_unorm_block = 149,
    etc2_r8g8b8a1_srgb_block = 150,

    etc2_r8g8b8a8_unorm_block = 151,
    etc2_r8g8b8a8_srgb_block = 152,

    eac_r11_unorm_block = 153,
    eac_r11_snorm_block = 154,

    eac_r11g11_unorm_block = 155,
    eac_r11g11_snorm_block = 156,

    astc_4x4_unorm_block = 157,
    astc_4x4_srgb_block = 158,

    astc_5x4_unorm_block = 159,
    astc_5x4_srgb_block = 160,

    astc_5x5_unorm_block = 161,
    astc_5x5_srgb_block = 162,

    astc_6x5_unorm_block = 163,
    astc_6x5_srgb_block = 164,

    astc_6x6_unorm_block = 165,
    astc_6x6_srgb_block = 166,

    astc_8x5_unorm_block = 167,
    astc_8x5_srgb_block = 168,

    astc_8x6_unorm_block = 169,
    astc_8x6_srgb_block = 170,

    astc_8x8_unorm_block = 171,
    astc_8x8_srgb_block = 172,

    astc_10x5_unorm_block = 173,
    astc_10x5_srgb_block = 174,

    astc_10x6_unorm_block = 175,
    astc_10x6_srgb_block = 176,

    astc_10x8_unorm_block = 177,
    astc_10x8_srgb_block = 178,

    astc_10x10_unorm_block = 179,
    astc_10x10_srgb_block = 180,

    astc_12x10_unorm_block = 181,
    astc_12x10_srgb_block = 182,

    astc_12x12_unorm_block = 183,
    astc_12x12_srgb_block = 184,

    // Provided by VK_VERSION_1_1

    g8b8g8r8_422_unorm = 1000156000,
    b8g8r8g8_422_unorm = 1000156001,
    g8_b8_r8_3plane_420_unorm = 1000156002,
    g8_b8r8_2plane_420_unorm = 1000156003,
    g8_b8_r8_3plane_422_unorm = 1000156004,
    g8_b8r8_2plane_422_unorm = 1000156005,
    g8_b8_r8_3plane_444_unorm = 1000156006,
    r10x6_unorm_pack16 = 1000156007,
    r10x6g10x6_unorm_2pack16 = 1000156008,
    r10x6g10x6b10x6a10x6_unorm_4pack16 = 1000156009,
    g10x6b10x6g10x6r10x6_422_unorm_4pack16 = 1000156010,
    b10x6g10x6r10x6g10x6_422_unorm_4pack16 = 1000156011,
    g10x6_b10x6_r10x6_3plane_420_unorm_3pack16 = 1000156012,
    g10x6_b10x6r10x6_2plane_420_unorm_3pack16 = 1000156013,
    g10x6_b10x6_r10x6_3plane_422_unorm_3pack16 = 1000156014,
    g10x6_b10x6r10x6_2plane_422_unorm_3pack16 = 1000156015,
    g10x6_b10x6_r10x6_3plane_444_unorm_3pack16 = 1000156016,
    r12x4_unorm_pack16 = 1000156017,
    r12x4g12x4_unorm_2pack16 = 1000156018,
    r12x4g12x4b12x4a12x4_unorm_4pack16 = 1000156019,
    g12x4b12x4g12x4r12x4_422_unorm_4pack16 = 1000156020,
    b12x4g12x4r12x4g12x4_422_unorm_4pack16 = 1000156021,
    g12x4_b12x4_r12x4_3plane_420_unorm_3pack16 = 1000156022,
    g12x4_b12x4r12x4_2plane_420_unorm_3pack16 = 1000156023,
    g12x4_b12x4_r12x4_3plane_422_unorm_3pack16 = 1000156024,
    g12x4_b12x4r12x4_2plane_422_unorm_3pack16 = 1000156025,
    g12x4_b12x4_r12x4_3plane_444_unorm_3pack16 = 1000156026,
    g16b16g16r16_422_unorm = 1000156027,
    b16g16r16g16_422_unorm = 1000156028,
    g16_b16_r16_3plane_420_unorm = 1000156029,
    g16_b16r16_2plane_420_unorm = 1000156030,
    g16_b16_r16_3plane_422_unorm = 1000156031,
    g16_b16r16_2plane_422_unorm = 1000156032,
    g16_b16_r16_3plane_444_unorm = 1000156033,

    // Provided by VK_VERSION_1_3

    g8_b8r8_2plane_444_unorm = 1000330000,
    g10x6_b10x6r10x6_2plane_444_unorm_3pack16 = 1000330001,
    g12x4_b12x4r12x4_2plane_444_unorm_3pack16 = 1000330002,
    g16_b16r16_2plane_444_unorm = 1000330003,

    a4r4g4b4_unorm_pack16 = 1000340000,
    a4b4g4r4_unorm_pack16 = 1000340001,

    astc_4x4_sfloat_block = 1000066000,
    astc_5x4_sfloat_block = 1000066001,
    astc_5x5_sfloat_block = 1000066002,
    astc_6x5_sfloat_block = 1000066003,
    astc_6x6_sfloat_block = 1000066004,
    astc_8x5_sfloat_block = 1000066005,
    astc_8x6_sfloat_block = 1000066006,
    astc_8x8_sfloat_block = 1000066007,
    astc_10x5_sfloat_block = 1000066008,
    astc_10x6_sfloat_block = 1000066009,
    astc_10x8_sfloat_block = 1000066010,
    astc_10x10_sfloat_block = 1000066011,
    astc_12x10_sfloat_block = 1000066012,
    astc_12x12_sfloat_block = 1000066013,

    // Provided by VK_IMG_format_pvrtc

    pvrtc1_2bpp_unorm_block_img = 1000054000,
    pvrtc1_4bpp_unorm_block_img = 1000054001,
    pvrtc2_2bpp_unorm_block_img = 1000054002,
    pvrtc2_4bpp_unorm_block_img = 1000054003,
    pvrtc1_2bpp_srgb_block_img = 1000054004,
    pvrtc1_4bpp_srgb_block_img = 1000054005,
    pvrtc2_2bpp_srgb_block_img = 1000054006,
    pvrtc2_4bpp_srgb_block_img = 1000054007,

    // Provided by VK_NV_optical_flow
    r16g16_s10_5_1_NV = 1000464000,

    // Provided by VK_KHR_maintenance5
    a1b5g5r5_unorm_pack16_khr = 1000470000,
    a8_unorm_khr = 1000470001,

    //   // Provided by VK_EXT_texture_compression_astc_hdr
    //     VK_FORMAT_ASTC_4x4_SFLOAT_BLOCK_EXT = VK_FORMAT_ASTC_4x4_SFLOAT_BLOCK,
    //   // Provided by VK_EXT_texture_compression_astc_hdr
    //     VK_FORMAT_ASTC_5x4_SFLOAT_BLOCK_EXT = VK_FORMAT_ASTC_5x4_SFLOAT_BLOCK,
    //   // Provided by VK_EXT_texture_compression_astc_hdr
    //     VK_FORMAT_ASTC_5x5_SFLOAT_BLOCK_EXT = VK_FORMAT_ASTC_5x5_SFLOAT_BLOCK,
    //   // Provided by VK_EXT_texture_compression_astc_hdr
    //     VK_FORMAT_ASTC_6x5_SFLOAT_BLOCK_EXT = VK_FORMAT_ASTC_6x5_SFLOAT_BLOCK,
    //   // Provided by VK_EXT_texture_compression_astc_hdr
    //     VK_FORMAT_ASTC_6x6_SFLOAT_BLOCK_EXT = VK_FORMAT_ASTC_6x6_SFLOAT_BLOCK,
    //   // Provided by VK_EXT_texture_compression_astc_hdr
    //     VK_FORMAT_ASTC_8x5_SFLOAT_BLOCK_EXT = VK_FORMAT_ASTC_8x5_SFLOAT_BLOCK,
    //   // Provided by VK_EXT_texture_compression_astc_hdr
    //     VK_FORMAT_ASTC_8x6_SFLOAT_BLOCK_EXT = VK_FORMAT_ASTC_8x6_SFLOAT_BLOCK,
    //   // Provided by VK_EXT_texture_compression_astc_hdr
    //     VK_FORMAT_ASTC_8x8_SFLOAT_BLOCK_EXT = VK_FORMAT_ASTC_8x8_SFLOAT_BLOCK,
    //   // Provided by VK_EXT_texture_compression_astc_hdr
    //     VK_FORMAT_ASTC_10x5_SFLOAT_BLOCK_EXT = VK_FORMAT_ASTC_10x5_SFLOAT_BLOCK,
    //   // Provided by VK_EXT_texture_compression_astc_hdr
    //     VK_FORMAT_ASTC_10x6_SFLOAT_BLOCK_EXT = VK_FORMAT_ASTC_10x6_SFLOAT_BLOCK,
    //   // Provided by VK_EXT_texture_compression_astc_hdr
    //     VK_FORMAT_ASTC_10x8_SFLOAT_BLOCK_EXT = VK_FORMAT_ASTC_10x8_SFLOAT_BLOCK,
    //   // Provided by VK_EXT_texture_compression_astc_hdr
    //     VK_FORMAT_ASTC_10x10_SFLOAT_BLOCK_EXT = VK_FORMAT_ASTC_10x10_SFLOAT_BLOCK,
    //   // Provided by VK_EXT_texture_compression_astc_hdr
    //     VK_FORMAT_ASTC_12x10_SFLOAT_BLOCK_EXT = VK_FORMAT_ASTC_12x10_SFLOAT_BLOCK,
    //   // Provided by VK_EXT_texture_compression_astc_hdr
    //     VK_FORMAT_ASTC_12x12_SFLOAT_BLOCK_EXT = VK_FORMAT_ASTC_12x12_SFLOAT_BLOCK,

    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G8B8G8R8_422_UNORM_KHR = VK_FORMAT_G8B8G8R8_422_UNORM,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_B8G8R8G8_422_UNORM_KHR = VK_FORMAT_B8G8R8G8_422_UNORM,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G8_B8_R8_3PLANE_420_UNORM_KHR = VK_FORMAT_G8_B8_R8_3PLANE_420_UNORM,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G8_B8R8_2PLANE_420_UNORM_KHR = VK_FORMAT_G8_B8R8_2PLANE_420_UNORM,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G8_B8_R8_3PLANE_422_UNORM_KHR = VK_FORMAT_G8_B8_R8_3PLANE_422_UNORM,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G8_B8R8_2PLANE_422_UNORM_KHR = VK_FORMAT_G8_B8R8_2PLANE_422_UNORM,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G8_B8_R8_3PLANE_444_UNORM_KHR = VK_FORMAT_G8_B8_R8_3PLANE_444_UNORM,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_R10X6_UNORM_PACK16_KHR = VK_FORMAT_R10X6_UNORM_PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_R10X6G10X6_UNORM_2PACK16_KHR = VK_FORMAT_R10X6G10X6_UNORM_2PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_R10X6G10X6B10X6A10X6_UNORM_4PACK16_KHR = VK_FORMAT_R10X6G10X6B10X6A10X6_UNORM_4PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G10X6B10X6G10X6R10X6_422_UNORM_4PACK16_KHR = VK_FORMAT_G10X6B10X6G10X6R10X6_422_UNORM_4PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_B10X6G10X6R10X6G10X6_422_UNORM_4PACK16_KHR = VK_FORMAT_B10X6G10X6R10X6G10X6_422_UNORM_4PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G10X6_B10X6_R10X6_3PLANE_420_UNORM_3PACK16_KHR = VK_FORMAT_G10X6_B10X6_R10X6_3PLANE_420_UNORM_3PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G10X6_B10X6R10X6_2PLANE_420_UNORM_3PACK16_KHR = VK_FORMAT_G10X6_B10X6R10X6_2PLANE_420_UNORM_3PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G10X6_B10X6_R10X6_3PLANE_422_UNORM_3PACK16_KHR = VK_FORMAT_G10X6_B10X6_R10X6_3PLANE_422_UNORM_3PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G10X6_B10X6R10X6_2PLANE_422_UNORM_3PACK16_KHR = VK_FORMAT_G10X6_B10X6R10X6_2PLANE_422_UNORM_3PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G10X6_B10X6_R10X6_3PLANE_444_UNORM_3PACK16_KHR = VK_FORMAT_G10X6_B10X6_R10X6_3PLANE_444_UNORM_3PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_R12X4_UNORM_PACK16_KHR = VK_FORMAT_R12X4_UNORM_PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_R12X4G12X4_UNORM_2PACK16_KHR = VK_FORMAT_R12X4G12X4_UNORM_2PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_R12X4G12X4B12X4A12X4_UNORM_4PACK16_KHR = VK_FORMAT_R12X4G12X4B12X4A12X4_UNORM_4PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G12X4B12X4G12X4R12X4_422_UNORM_4PACK16_KHR = VK_FORMAT_G12X4B12X4G12X4R12X4_422_UNORM_4PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_B12X4G12X4R12X4G12X4_422_UNORM_4PACK16_KHR = VK_FORMAT_B12X4G12X4R12X4G12X4_422_UNORM_4PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G12X4_B12X4_R12X4_3PLANE_420_UNORM_3PACK16_KHR = VK_FORMAT_G12X4_B12X4_R12X4_3PLANE_420_UNORM_3PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G12X4_B12X4R12X4_2PLANE_420_UNORM_3PACK16_KHR = VK_FORMAT_G12X4_B12X4R12X4_2PLANE_420_UNORM_3PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G12X4_B12X4_R12X4_3PLANE_422_UNORM_3PACK16_KHR = VK_FORMAT_G12X4_B12X4_R12X4_3PLANE_422_UNORM_3PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G12X4_B12X4R12X4_2PLANE_422_UNORM_3PACK16_KHR = VK_FORMAT_G12X4_B12X4R12X4_2PLANE_422_UNORM_3PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G12X4_B12X4_R12X4_3PLANE_444_UNORM_3PACK16_KHR = VK_FORMAT_G12X4_B12X4_R12X4_3PLANE_444_UNORM_3PACK16,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G16B16G16R16_422_UNORM_KHR = VK_FORMAT_G16B16G16R16_422_UNORM,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_B16G16R16G16_422_UNORM_KHR = VK_FORMAT_B16G16R16G16_422_UNORM,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G16_B16_R16_3PLANE_420_UNORM_KHR = VK_FORMAT_G16_B16_R16_3PLANE_420_UNORM,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G16_B16R16_2PLANE_420_UNORM_KHR = VK_FORMAT_G16_B16R16_2PLANE_420_UNORM,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G16_B16_R16_3PLANE_422_UNORM_KHR = VK_FORMAT_G16_B16_R16_3PLANE_422_UNORM,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G16_B16R16_2PLANE_422_UNORM_KHR = VK_FORMAT_G16_B16R16_2PLANE_422_UNORM,
    //   // Provided by VK_KHR_sampler_ycbcr_conversion
    //     VK_FORMAT_G16_B16_R16_3PLANE_444_UNORM_KHR = VK_FORMAT_G16_B16_R16_3PLANE_444_UNORM,

    //   // Provided by VK_EXT_ycbcr_2plane_444_formats
    //     VK_FORMAT_G8_B8R8_2PLANE_444_UNORM_EXT = VK_FORMAT_G8_B8R8_2PLANE_444_UNORM,
    //   // Provided by VK_EXT_ycbcr_2plane_444_formats
    //     VK_FORMAT_G10X6_B10X6R10X6_2PLANE_444_UNORM_3PACK16_EXT = VK_FORMAT_G10X6_B10X6R10X6_2PLANE_444_UNORM_3PACK16,
    //   // Provided by VK_EXT_ycbcr_2plane_444_formats
    //     VK_FORMAT_G12X4_B12X4R12X4_2PLANE_444_UNORM_3PACK16_EXT = VK_FORMAT_G12X4_B12X4R12X4_2PLANE_444_UNORM_3PACK16,
    //   // Provided by VK_EXT_ycbcr_2plane_444_formats
    //     VK_FORMAT_G16_B16R16_2PLANE_444_UNORM_EXT = VK_FORMAT_G16_B16R16_2PLANE_444_UNORM,

    //   // Provided by VK_EXT_4444_formats
    //     VK_FORMAT_A4R4G4B4_UNORM_PACK16_EXT = VK_FORMAT_A4R4G4B4_UNORM_PACK16,
    //   // Provided by VK_EXT_4444_formats
    //     VK_FORMAT_A4B4G4R4_UNORM_PACK16_EXT = VK_FORMAT_A4B4G4R4_UNORM_PACK16,
};

pub const VkSurfaceFormatKHR = struct {
    format: VkFormat,
    colorSpace: VkColorSpaceKHR,

    fn from_vulkan_ty(surface_format: vulkan.VkSurfaceFormatKHR) VkSurfaceFormatKHR {
        return VkSurfaceFormatKHR{
            .format = @enumFromInt(surface_format.format),
            .colorSpace = @enumFromInt(surface_format.colorSpace),
        };
    }
};

pub const vkGetPhysicalDeviceSurfaceFormatsKHRError = error{
    VK_INCOMPLETE,
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
    VK_ERROR_SURFACE_LOST_KHR,

    OutOfMemory,
};

pub fn vkGetPhysicalDeviceSurfaceFormatsKHR(
    allocator: std.mem.Allocator,
    physicalDevice: VkPhysicalDevice,
    surface: VkSurfaceKHR,
) vkGetPhysicalDeviceSurfaceFormatsKHRError![]VkSurfaceFormatKHR {
    var format_count: u32 = undefined;
    var result = vulkan.vkGetPhysicalDeviceSurfaceFormatsKHR(
        physicalDevice,
        surface,
        &format_count,
        null,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_INCOMPLETE => return vkGetPhysicalDeviceSurfaceFormatsKHRError.VK_INCOMPLETE,
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkGetPhysicalDeviceSurfaceFormatsKHRError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkGetPhysicalDeviceSurfaceFormatsKHRError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_SURFACE_LOST_KHR => return vkGetPhysicalDeviceSurfaceFormatsKHRError.VK_ERROR_SURFACE_LOST_KHR,
            else => unreachable,
        }
    }

    if (format_count == 0) {
        return &.{};
    }

    var formats = try allocator.alloc(vulkan.VkSurfaceFormatKHR, format_count);
    defer allocator.free(formats);
    result = vulkan.vkGetPhysicalDeviceSurfaceFormatsKHR(
        physicalDevice,
        surface,
        &format_count,
        formats.ptr,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_INCOMPLETE => return vkGetPhysicalDeviceSurfaceFormatsKHRError.VK_INCOMPLETE,
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkGetPhysicalDeviceSurfaceFormatsKHRError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkGetPhysicalDeviceSurfaceFormatsKHRError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_SURFACE_LOST_KHR => return vkGetPhysicalDeviceSurfaceFormatsKHRError.VK_ERROR_SURFACE_LOST_KHR,
            else => unreachable,
        }
    }

    var to_return = try allocator.alloc(VkSurfaceFormatKHR, format_count);
    var i: usize = 0;
    while (i < format_count) : (i += 1) {
        to_return[i] = VkSurfaceFormatKHR.from_vulkan_ty(formats[i]);
    }

    return to_return;
}

pub const VkPresentModeKHR = enum(c_uint) {
    immediate_khr = 0,
    mailbox_khr = 1,
    fifo_khr = 2,
    fifo_relaxed_khr = 3,

    // Provided by VK_KHR_shared_presentable_image
    shared_demand_refresh_khr = 1000111000,
    shared_continuous_refresh_khr = 1000111001,
};

pub const vkGetPhysicalDeviceSurfacePresentModesKHRError = error{
    VK_INCOMPLETE,
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
    VK_ERROR_SURFACE_LOST_KHR,

    OutOfMemory,
};

pub fn vkGetPhysicalDeviceSurfacePresentModesKHR(
    allocator: std.mem.Allocator,
    physicalDevice: VkPhysicalDevice,
    surface: VkSurfaceKHR,
) vkGetPhysicalDeviceSurfacePresentModesKHRError![]VkPresentModeKHR {
    var present_mode_count: u32 = undefined;
    var result = vulkan.vkGetPhysicalDeviceSurfacePresentModesKHR(
        physicalDevice,
        surface,
        &present_mode_count,
        null,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_INCOMPLETE => return vkGetPhysicalDeviceSurfacePresentModesKHRError.VK_INCOMPLETE,
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkGetPhysicalDeviceSurfacePresentModesKHRError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkGetPhysicalDeviceSurfacePresentModesKHRError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_SURFACE_LOST_KHR => return vkGetPhysicalDeviceSurfacePresentModesKHRError.VK_ERROR_SURFACE_LOST_KHR,
            else => unreachable,
        }
    }

    if (present_mode_count == 0) {
        return &.{};
    }

    var present_modes = try allocator.alloc(vulkan.VkPresentModeKHR, present_mode_count);
    defer allocator.free(present_modes);
    result = vulkan.vkGetPhysicalDeviceSurfacePresentModesKHR(
        physicalDevice,
        surface,
        &present_mode_count,
        present_modes.ptr,
    );
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_INCOMPLETE => return vkGetPhysicalDeviceSurfacePresentModesKHRError.VK_INCOMPLETE,
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkGetPhysicalDeviceSurfacePresentModesKHRError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkGetPhysicalDeviceSurfacePresentModesKHRError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_SURFACE_LOST_KHR => return vkGetPhysicalDeviceSurfacePresentModesKHRError.VK_ERROR_SURFACE_LOST_KHR,
            else => unreachable,
        }
    }

    var to_return = try allocator.alloc(VkPresentModeKHR, present_mode_count);
    var i: usize = 0;
    while (i < present_mode_count) : (i += 1) {
        to_return[i] = @enumFromInt(present_modes[i]);
    }

    return to_return;
}
