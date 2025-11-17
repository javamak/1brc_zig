const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Get the dependency object from the builder
    const ordered_dep = b.dependency("ordered", .{});

    // 2. Create a module for the dependency
    const ordered_module = ordered_dep.module("ordered");

    // 3. Create your executable module and add ordered as import
    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_module.addImport("ordered", ordered_module);

    // 4. Create executable with the module
    const exe = b.addExecutable(.{
        .name = "1brc_zig",
        .root_module = exe_module,
    });

    b.installArtifact(exe);
}
