const std = @import("std");

pub fn addDearImGuiTo(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const module = b.createModule(.{
        .root_source_file = b.path("libs/zig-imgui/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const imgui_path = "deps/imgui";
    const bindings_path = "deps/imgui_gen";

    // Include paths
    module.addIncludePath(b.path(imgui_path));
    module.addIncludePath(b.path(bindings_path));

    // Add all C++ source files together to ensure proper linking
    module.addCSourceFiles(.{
        .files = &.{
            imgui_path ++ "/imgui.cpp",
            imgui_path ++ "/imgui_draw.cpp",
            imgui_path ++ "/imgui_widgets.cpp",
            imgui_path ++ "/imgui_tables.cpp",
            imgui_path ++ "/imgui_demo.cpp",
            bindings_path ++ "/dcimgui.cpp",
            bindings_path ++ "/dcimgui_internal.cpp",
        },
        .flags = &.{"-DIMGUI_DISABLE_OBSOLETE_FUNCTIONS"},
    });

    module.link_libc = true;
    module.link_libcpp = true;
    return module;
}
