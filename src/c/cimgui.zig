pub usingnamespace @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", {});
    @cInclude("cimgui.h");
    @cDefine("CIMGUI_USE_VULKAN", {});
    @cDefine("CIMGUI_USE_GLFW", {});
    @cInclude("cimgui_impl.h");
});
