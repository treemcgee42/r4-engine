pub const glfw = struct {
    pub usingnamespace @cImport({
        @cDefine("GLFW_INCLUDE_VULKAN", {});
        @cInclude("GLFW/glfw3.h");
    });
};

pub const cglm = struct {
    pub usingnamespace @cImport({
        @cInclude("cglm/cglm.h");
        @cInclude("cglm/call.h");
    });
};

pub const vulkan = struct {
    pub usingnamespace @cImport({
        @cInclude("vulkan/vulkan.h");
    });
};
