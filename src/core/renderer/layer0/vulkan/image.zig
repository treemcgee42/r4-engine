pub const vulkan = @import("vulkan");
pub const l0vk = @import("./vulkan.zig");

pub const VkImage = vulkan.VkImage;

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

pub const VkImageLayout = enum(c_uint) {
    undefined = 0,
    general = 1,
    color_attachment_optimal = 2,
    depth_stencil_attachment_optimal = 3,
    depth_stencil_read_only_optimal = 4,
    shader_read_only_optimal = 5,
    transfer_src_optimal = 6,
    transfer_dst_optimal = 7,
    preinitialized = 8,
    depth_read_only_stencil_attachment_optimal = 1000117000,
    depth_attachment_stencil_read_only_optimal = 1000117001,
    depth_attachment_optimal = 1000241000,
    depth_read_only_optimal = 1000241001,
    stencil_attachment_optimal = 1000241002,
    stencil_read_only_optimal = 1000241003,
    read_only_optimal = 1000314000,
    attachment_optimal = 1000314001,
    present_src_khr = 1000001002,
    video_decode_dst_khr = 1000024000,
    video_decode_src_khr = 1000024001,
    video_decode_dpb_khr = 1000024002,
    shared_present_khr = 1000111000,
    fragment_density_map_optimal_ext = 1000218000,
    fragment_shading_rate_attachment_optimal_khr = 1000164003,
    video_encode_dst_khr = 1000299000,
    video_encode_src_khr = 1000299001,
    video_encode_dpb_khr = 1000299002,
    feedback_loop_optimal_ext = 1000339000,
};

// --- ImageView.

pub const VkImageView = vulkan.VkImageView;

pub const VkImageViewCreateFlags = packed struct(u32) {
    fragment_density_map_dynamic_ext: bool = false,
    fragment_density_map_deferred_ext: bool = false,
    descriptor_buffer_capture_replay_ext: bool = false,
    _: u1 = 0,

    _a: u28 = 0,

    pub const Bits = enum(c_uint) {
        fragment_density_map_dynamic_ext = 0x00000001,
        fragment_density_map_deferred_ext = 0x00000002,
        descriptor_buffer_capture_replay_ext = 0x00000004,
    };
};

pub const VkImageViewType = enum(c_uint) {
    ty_1d = 0,
    ty_2d = 1,
    ty_3d = 2,
    cube = 3,
    ty_1d_array = 4,
    ty_2d_array = 5,
    cube_array = 6,

    max_enum = 2147483647,
};

pub const VkComponentSwizzle = enum(c_uint) {
    identity = 0,
    zero = 1,
    one = 2,
    r = 3,
    g = 4,
    b = 5,
    a = 6,

    max_enum = 2147483647,
};

pub const VkComponentMapping = struct {
    r: VkComponentSwizzle,
    g: VkComponentSwizzle,
    b: VkComponentSwizzle,
    a: VkComponentSwizzle,

    pub fn to_vulkan_ty(self: *const VkComponentMapping) vulkan.VkComponentMapping {
        return vulkan.VkComponentMapping{
            .r = @intFromEnum(self.r),
            .g = @intFromEnum(self.g),
            .b = @intFromEnum(self.b),
            .a = @intFromEnum(self.a),
        };
    }
};

pub const VkImageAspectFlags = packed struct(u32) {
    color: bool = false,
    depth: bool = false,
    stencil: bool = false,
    metadata: bool = false,

    plane_0: bool = false,
    plane_1: bool = false,
    plane_2: bool = false,
    memory_plane_0: bool = false,

    memory_plane_1: bool = false,
    memory_plane_2: bool = false,
    memory_plane_3: bool = false,
    _: u1 = 0,

    _a: u20 = 0,

    pub const Bits = enum(c_uint) {
        color = 0x00000001,
        depth = 0x00000002,
        stencil = 0x00000004,
        metadata = 0x00000008,

        plane_0 = 0x00000010,
        plane_1 = 0x00000020,
        plane_2 = 0x00000040,
        memory_plane_0 = 0x00000080,

        memory_plane_1 = 0x00000100,
        memory_plane_2 = 0x00000200,
        memory_plane_3 = 0x00000400,
    };
};

pub const VkImageSubresourceRange = struct {
    aspectMask: VkImageAspectFlags = .{},
    baseMipLevel: u32,
    levelCount: u32,
    baseArrayLayer: u32,
    layerCount: u32,

    pub fn to_vulkan_ty(self: *const VkImageSubresourceRange) vulkan.VkImageSubresourceRange {
        return vulkan.VkImageSubresourceRange{
            .aspectMask = @bitCast(self.aspectMask),
            .baseMipLevel = self.baseMipLevel,
            .levelCount = self.levelCount,
            .baseArrayLayer = self.baseArrayLayer,
            .layerCount = self.layerCount,
        };
    }
};

pub const VkImageViewCreateInfo = struct {
    pNext: ?*const anyopaque = null,
    flags: VkImageViewCreateFlags = .{},
    image: VkImage,
    viewType: VkImageViewType,
    format: VkFormat,
    components: VkComponentMapping,
    subresourceRange: VkImageSubresourceRange,

    pub fn to_vulkan_ty(self: *const VkImageViewCreateInfo) vulkan.VkImageViewCreateInfo {
        return .{
            .sType = vulkan.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = self.pNext,
            .flags = @bitCast(self.flags),
            .image = self.image,
            .viewType = @intFromEnum(self.viewType),
            .format = @intFromEnum(self.format),
            .components = self.components.to_vulkan_ty(),
            .subresourceRange = self.subresourceRange.to_vulkan_ty(),
        };
    }
};

pub const vkCreateImageViewError = error{
    VK_ERROR_OUT_OF_HOST_MEMORY,
    VK_ERROR_OUT_OF_DEVICE_MEMORY,
    VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS_KHR,
};

pub fn vkCreateImageView(
    device: l0vk.VkDevice,
    pCreateInfo: *const VkImageViewCreateInfo,
    pAllocator: [*c]const l0vk.VkAllocationCallbacks,
) vkCreateImageViewError!VkImageView {
    const create_info = pCreateInfo.to_vulkan_ty();

    var image_view: l0vk.VkImageView = undefined;
    const result = vulkan.vkCreateImageView(device, &create_info, pAllocator, &image_view);
    if (result != vulkan.VK_SUCCESS) {
        switch (result) {
            vulkan.VK_ERROR_OUT_OF_HOST_MEMORY => return vkCreateImageViewError.VK_ERROR_OUT_OF_HOST_MEMORY,
            vulkan.VK_ERROR_OUT_OF_DEVICE_MEMORY => return vkCreateImageViewError.VK_ERROR_OUT_OF_DEVICE_MEMORY,
            vulkan.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS_KHR => return vkCreateImageViewError.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS_KHR,
            else => unreachable,
        }
    }

    return image_view;
}

pub inline fn vkDestroyImageView(
    device: l0vk.VkDevice,
    imageView: VkImageView,
    pAllocator: [*c]const l0vk.VkAllocationCallbacks,
) void {
    vulkan.vkDestroyImageView(device, imageView, pAllocator);
}
