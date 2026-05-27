const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wayplug_mod = b.addModule("wayplug", .{
        .root_source_file = b.path("src/wayplug.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "wayplug",
        .root_module = wayplug_mod,
    });
    lib.installHeader(b.path("include/wayplug.h"), "wayplug.h");
    b.installArtifact(lib);

    const test_step = b.step("test", "Run unit and C ABI smoke tests");

    // Unit tests: drive the in-file `test` blocks under src/.
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wayplug.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);

    // Integration tests: each file imports the `wayplug` module.
    const integration_test_files = [_][]const u8{
        "tests/data_tests.zig",
        "tests/engine_tests.zig",
        "tests/protocol_smoke_tests.zig",
    };
    for (integration_test_files) |path| {
        const mod = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        mod.addImport("wayplug", wayplug_mod);
        const t = b.addTest(.{ .root_module = mod });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }

    // C ABI smoke: compile c_abi_smoke.c against the static lib.
    const c_abi_smoke = b.addExecutable(.{
        .name = "wayplug-c-abi-smoke",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    c_abi_smoke.root_module.addCSourceFile(.{
        .file = b.path("tests/c_abi_smoke.c"),
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" },
    });
    c_abi_smoke.root_module.addIncludePath(b.path("include"));
    c_abi_smoke.root_module.linkLibrary(lib);
    test_step.dependOn(&b.addRunArtifact(c_abi_smoke).step);
}
