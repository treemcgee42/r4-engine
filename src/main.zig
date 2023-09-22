const std = @import("std");

const glfw = struct {
    pub usingnamespace @cImport({
        @cDefine("GLFW_INCLUDE_VULKAN", {});
        @cInclude("GLFW/glfw3.h");
    });
};

const cglm = struct {
    pub usingnamespace @cImport({
        @cInclude("cglm/cglm.h");
        @cInclude("cglm/call.h");
    });
};

pub fn main() !void {
    _ = glfw.glfwInit();

    glfw.glfwWindowHint(glfw.GLFW_CLIENT_API, glfw.GLFW_NO_API);
    glfw.glfwWindowHint(glfw.GLFW_CLIENT_API, glfw.GLFW_NO_API);
    var window = glfw.glfwCreateWindow(800, 600, "Vulkan window", null, null);

    var extensions_count: u32 = 0;
    _ = glfw.vkEnumerateInstanceExtensionProperties(null, &extensions_count, null);

    std.debug.print("extensions supported = {}\n", .{extensions_count});

    var m1 = cglm.mat4{ cglm.vec4{ 1.0, 0.0, 0.0, 0.0 }, cglm.vec4{ 0.0, 1.0, 0.0, 0.0 }, cglm.vec4{ 0.0, 0.0, 1.0, 0.0 }, cglm.vec4{ 0.0, 0.0, 0.0, 1.0 } };
    var m2 = cglm.mat4{ cglm.vec4{ 1.0, 0.0, 0.0, 0.0 }, cglm.vec4{ 0.0, 1.0, 0.0, 0.0 }, cglm.vec4{ 0.0, 0.0, 1.0, 0.0 }, cglm.vec4{ 0.0, 0.0, 0.0, 1.0 } };
    var m3: cglm.mat4 = undefined;
    cglm.glmc_mat4_mul(&m3, &m1, &m2);

    while (glfw.glfwWindowShouldClose(window) == 0) {
        glfw.glfwPollEvents();
    }

    glfw.glfwDestroyWindow(window);

    glfw.glfwTerminate();
}
