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
};
