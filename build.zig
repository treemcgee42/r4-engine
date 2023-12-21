const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "game_engine",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    exe.linkLibCpp();

    // GLFW.
    link_glfw(b, exe, true);

    // CGLM.
    exe.addLibraryPath(.{ .path = "./external/cglm-0.9.1/build" });
    exe.linkSystemLibrary("cglm");
    exe.addIncludePath(.{ .path = "./external/cglm-0.9.1/include" });

    // VULKAN.
    exe.linkFramework("Metal");
    exe.linkFramework("Foundation");
    exe.linkFramework("QuartzCore");
    exe.linkFramework("IOKit");
    exe.linkFramework("IOSurface");
    exe.linkFramework("Cocoa");
    exe.linkFramework("CoreVideo");

    link_vulkan(b, exe, true);

    // VMA
    exe.addIncludePath(.{ .path = "./external/vma" });
    exe.addCSourceFile(.{
        .file = .{ .path = "./external/vma/vk_mem_alloc_impl.cpp" },
        .flags = &[_][]const u8{},
    });
    const vma_module = b.createModule(.{
        .source_file = .{ .path = "src/c/vma.zig" },
    });
    exe.addModule("vma", vma_module);

    // STB_IMAGE.
    exe.addIncludePath(.{ .path = "./external/stb_image" });
    exe.addCSourceFile(.{
        .file = .{ .path = "./external/stb_image/stb_image_impl.c" },
        .flags = &[_][]const u8{},
    });

    // FAST_OBJ.
    exe.addIncludePath(.{ .path = "./external/fast_obj" });
    exe.addCSourceFile(.{
        .file = .{ .path = "./external/fast_obj/fast_obj.c" },
        .flags = &[_][]const u8{},
    });

    // CGLTF
    exe.addIncludePath(.{ .path = "./external/cgltf" });
    exe.addCSourceFile(.{
        .file = .{ .path = "./external/cgltf/cgltf_impl.c" },
        .flags = &[_][]const u8{},
    });
    const cgltf_module = b.createModule(.{
        .source_file = .{ .path = "src/c/cgltf.zig" },
    });
    exe.addModule("cgltf", cgltf_module);

    // CIMGUI.
    exe.addIncludePath(.{ .path = "./external/cimgui" });
    exe.addIncludePath(.{ .path = "./external/cimgui/generator/output" });
    exe.linkLibrary(build_cimgui(b, target));
    const cimgui_module = b.createModule(.{
        .source_file = .{ .path = "src/c/cimgui.zig" },
    });
    exe.addModule("cimgui", cimgui_module);

    // r4 ecs
    exe.linkLibrary(build_libr4ecs(b, optimize, target));

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

fn link_glfw(b: *std.Build, exe: *std.build.Step.Compile, add_module: bool) void {
    exe.addLibraryPath(.{ .path = "/opt/homebrew/opt/glfw/lib" });
    exe.linkSystemLibrary("glfw.3.3");
    exe.addIncludePath(.{ .path = "/opt/homebrew/opt/glfw/include" });

    if (add_module) {
        const glfw_module = b.createModule(.{
            .source_file = .{ .path = "src/c/glfw.zig" },
        });
        exe.addModule("glfw", glfw_module);
    }
}

fn link_vulkan(b: *std.Build, exe: *std.build.Step.Compile, add_module: bool) void {
    exe.addLibraryPath(.{ .path = "/Users/ogmalladii/VulkanSDK/1.3.261.1/macOS/lib" });
    // exe.linkSystemLibrary("vulkan.1");
    exe.linkSystemLibrary("vulkan.1.3.261");
    exe.addIncludePath(.{ .path = "/Users/ogmalladii/VulkanSDK/1.3.261.1/macOS/include" });

    if (add_module) {
        const vulkan_module = b.createModule(.{
            .source_file = .{ .path = "src/c/vulkan.zig" },
        });

        exe.addModule("vulkan", vulkan_module);
    }
}

fn build_cimgui(b: *std.Build, target: std.zig.CrossTarget) *std.build.Step.Compile {
    const dir = "external/cimgui";
    const sources = [_][]const u8{
        "cimgui.cpp",
        "imgui/imgui.cpp",
        "imgui/imgui_draw.cpp",
        "imgui/imgui_demo.cpp",
        "imgui/imgui_widgets.cpp",
        "imgui/imgui_tables.cpp",

        "imgui/backends/imgui_impl_vulkan.cpp",
        "imgui/backends/imgui_impl_glfw.cpp",
    };

    const cimgui = b.addSharedLibrary(.{
        .name = "cimgui",
        .target = target,
        .optimize = .ReleaseFast,
    });

    cimgui.linkLibC();
    cimgui.linkLibCpp();

    link_glfw(b, cimgui, false);
    link_vulkan(b, cimgui, false);

    cimgui.addIncludePath(.{ .path = dir });
    cimgui.addIncludePath(.{ .path = dir ++ "/imgui" });

    const cpp_flags: []const []const u8 = &[_][]const u8{
        "-O2",
        "-ffunction-sections",
        "-fdata-sections",
        "-DIMGUI_DISABLE_OBSOLETE_FUNCTIONS=1",
        "-DIMGUI_IMPL_API=extern \"C\" ",
        "-Dcimgui_EXPORTS",
    };

    inline for (sources) |src| {
        cimgui.addCSourceFile(.{
            .file = .{ .path = dir ++ "/" ++ src },
            .flags = cpp_flags,
        });
    }

    return cimgui;
}

fn build_libr4ecs(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    target: std.zig.CrossTarget,
) *std.build.Step.Compile {
    const libr4ecs = b.addSharedLibrary(.{
        .name = "r4ecs",
        .root_source_file = .{ .path = "src/ecs/components.zig" },
        .target = target,
        .optimize = optimize,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });

    b.installArtifact(libr4ecs);

    return libr4ecs;
}
