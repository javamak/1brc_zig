const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 3. Create your executable module and add ordered as import
    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 4. Create executable with the module
    const exe = b.addExecutable(.{
        .name = "1brc_zig",
        .root_module = exe_module,
    });

    b.installArtifact(exe);
}
