pub const glfw = struct {
    pub usingnamespace @cImport({
        @cDefine("GLFW_INCLUDE_VULKAN", {});
        @cInclude("GLFW/glfw3.h");
    });
};

pub const cglm = struct {
    pub usingnamespace @cImport({
        @cDefine("CGLM_FORCE_DEPTH_ZERO_TO_ONE", "");
        @cInclude("cglm/cglm.h");
        @cInclude("cglm/call.h");
    });
};

pub const vulkan = struct {
    pub usingnamespace @cImport({
        @cInclude("vulkan/vulkan.h");
    });
};

pub const stb_image = struct {
    pub usingnamespace @cImport({
        @cInclude("stb_image.h");
    });
};

pub const fast_obj = struct {
    pub usingnamespace @cImport({
        @cInclude("fast_obj.h");
    });
};

const c_string = @cImport({
    @cInclude("string.h");
});

pub const memcpy = c_string.memcpy;
