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

    // TODO: separate function to build r4_core module

    // debug utils
    const debug_utils_module = b.createModule(.{
        .source_file = .{ .path = "src/debug_utils/lib.zig" },
    });

    // ecs
    const ecs_module = b.createModule(.{
        .source_file = .{ .path = "src/ecs/lib.zig" },
        .dependencies = &.{
            .{
                .name = "debug_utils",
                .module = debug_utils_module,
            },
        },
    });

    // GLFW.
    const glfw_module = b.createModule(.{
        .source_file = .{ .path = "src/c/glfw.zig" },
    });

    // CGLM.

    const cglm_module = b.createModule(.{
        .source_file = .{ .path = "src/c/cglm.zig" },
    });

    // math
    const math_module = b.createModule(.{
        .source_file = .{ .path = "src/math.zig" },
        .dependencies = &.{
            .{
                .name = "cglm",
                .module = cglm_module,
            },
        },
    });

    // VULKAN.
    const vulkan_module = b.createModule(.{
        .source_file = .{ .path = "src/c/vulkan.zig" },
    });

    // VMA
    const vma_module = b.createModule(.{
        .source_file = .{ .path = "src/c/vma.zig" },
    });

    // CGLTF
    const cgltf_module = b.createModule(.{
        .source_file = .{ .path = "src/c/cgltf.zig" },
    });

    // CIMGUI.
    const cimgui_module = b.createModule(.{
        .source_file = .{ .path = "src/c/cimgui.zig" },
    });

    // r4-core
    const r4_core_module = b.createModule(.{
        .source_file = .{ .path = "src/core/lib.zig" },
        .dependencies = &.{
            .{
                .name = "ecs",
                .module = ecs_module,
            },
            .{
                .name = "debug_utils",
                .module = debug_utils_module,
            },
            .{
                .name = "glfw",
                .module = glfw_module,
            },
            .{
                .name = "vma",
                .module = vma_module,
            },
            .{
                .name = "cgltf",
                .module = cgltf_module,
            },
            .{
                .name = "cimgui",
                .module = cimgui_module,
            },
            .{
                .name = "vulkan",
                .module = vulkan_module,
            },
            .{
                .name = "math",
                .module = math_module,
            },
            .{
                .name = "cglm",
                .module = cglm_module,
            },
        },
    });

    build_examples(b, target, optimize, r4_core_module);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    var tests = b.addTest(.{
        .root_source_file = .{ .path = "tests/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    tests.addModule("r4_core", r4_core_module);

    const run_tests = b.addRunArtifact(tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
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

    cimgui.addLibraryPath(.{ .path = "/opt/homebrew/opt/glfw/lib" });
    cimgui.linkSystemLibrary("glfw.3.3");
    cimgui.addIncludePath(.{ .path = "/opt/homebrew/opt/glfw/include" });

    cimgui.addLibraryPath(.{ .path = "/Users/ogmalladii/VulkanSDK/1.3.261.1/macOS/lib" });
    // exe.linkSystemLibrary("vulkan.1");
    cimgui.linkSystemLibrary("vulkan.1.3.261");
    cimgui.addIncludePath(.{ .path = "/Users/ogmalladii/VulkanSDK/1.3.261.1/macOS/include" });

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

fn build_examples(
    b: *std.Build,
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
    r4_core: *std.build.Module,
) void {
    const Example = struct {
        name: []const u8,
        path: []const u8,
    };

    const examples = [_]Example{
        .{ .name = "hello_triangle", .path = "./examples/hello_triangle.zig" },
    };

    const build_all_examples = b.option(
        bool,
        "build_all_examples",
        "Build all examples",
    ) orelse false;

    inline for (examples) |example| {
        const build_option_name = "build_" ++ example.name ++ "_example";
        const build_this_example = b.option(
            bool,
            build_option_name,
            "Build the example '" ++ example.name ++ "'",
        ) orelse false;

        if (build_this_example or build_all_examples) {
            const exe = b.addExecutable(.{
                .name = example.name,
                .root_source_file = .{ .path = example.path },
                .target = target,
                .optimize = optimize,
            });

            exe.linkLibC();
            exe.linkLibCpp();

            exe.linkFramework("Metal");
            exe.linkFramework("Foundation");
            exe.linkFramework("QuartzCore");
            exe.linkFramework("IOKit");
            exe.linkFramework("IOSurface");
            exe.linkFramework("Cocoa");
            exe.linkFramework("CoreVideo");

            exe.addLibraryPath(.{ .path = "/opt/homebrew/opt/glfw/lib" });
            exe.linkSystemLibrary("glfw.3.3");
            exe.addIncludePath(.{ .path = "/opt/homebrew/opt/glfw/include" });

            exe.addLibraryPath(.{ .path = "/Users/ogmalladii/VulkanSDK/1.3.261.1/macOS/lib" });
            // exe.linkSystemLibrary("vulkan.1");
            exe.linkSystemLibrary("vulkan.1.3.261");
            exe.addIncludePath(.{ .path = "/Users/ogmalladii/VulkanSDK/1.3.261.1/macOS/include" });

            exe.addLibraryPath(.{ .path = "./external/cglm-0.9.1/build" });
            exe.linkSystemLibrary("cglm");
            exe.addIncludePath(.{ .path = "./external/cglm-0.9.1/include" }); // TODO: necessary?

            exe.addIncludePath(.{ .path = "./external/vma" });
            exe.addCSourceFile(.{
                .file = .{ .path = "./external/vma/vk_mem_alloc_impl.cpp" },
                .flags = &[_][]const u8{},
            });

            exe.addIncludePath(.{ .path = "./external/cgltf" });
            exe.addCSourceFile(.{
                .file = .{ .path = "./external/cgltf/cgltf_impl.c" },
                .flags = &[_][]const u8{},
            });

            exe.addIncludePath(.{ .path = "./external/cimgui" });
            exe.addIncludePath(.{ .path = "./external/cimgui/generator/output" });
            exe.linkLibrary(build_cimgui(b, target));

            exe.addModule("r4_core", r4_core);

            b.installArtifact(exe);
        }
    }
}
