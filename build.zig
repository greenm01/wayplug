const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const xdg = xdgProtocol(b);

    const wayplug_mod = b.addModule("wayplug", .{
        .root_source_file = b.path("src/wayplug.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    linkWayland(wayplug_mod);
    addXdgProtocol(wayplug_mod, xdg);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "wayplug",
        .root_module = wayplug_mod,
    });
    lib.installHeader(b.path("include/wayplug.h"), "wayplug.h");
    b.installArtifact(lib);

    const test_step = b.step("test", "Run unit and C ABI smoke tests");

    // Unit tests: drive the in-file `test` blocks under src/.
    const unit_test_mod = b.createModule(.{
        .root_source_file = b.path("src/wayplug.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    linkWayland(unit_test_mod);
    addXdgProtocol(unit_test_mod, xdg);
    const unit_tests = b.addTest(.{
        .root_module = unit_test_mod,
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
        linkWayland(mod);
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
    linkWayland(c_abi_smoke.root_module);
    test_step.dependOn(&b.addRunArtifact(c_abi_smoke).step);
}

const XdgProtocol = struct {
    client_header: std.Build.LazyPath,
    server_header: std.Build.LazyPath,
    private_code: std.Build.LazyPath,
};

fn linkWayland(module: *std.Build.Module) void {
    module.linkSystemLibrary("wayland-server", .{ .use_pkg_config = .yes });
    module.linkSystemLibrary("wayland-client", .{ .use_pkg_config = .yes });
}

fn xdgProtocol(b: *std.Build) XdgProtocol {
    const protocols_dir = b.option(
        []const u8,
        "wayland-protocols-dir",
        "Directory containing stable Wayland protocol XML files",
    ) orelse "/usr/share/wayland-protocols";
    const xml = std.Build.LazyPath{
        .cwd_relative = b.fmt("{s}/stable/xdg-shell/xdg-shell.xml", .{protocols_dir}),
    };

    const client = b.addSystemCommand(&.{ "wayland-scanner", "client-header" });
    client.addFileArg(xml);
    const client_header = client.addOutputFileArg("xdg-shell-client-protocol.h");

    const server = b.addSystemCommand(&.{ "wayland-scanner", "server-header" });
    server.addFileArg(xml);
    const server_header = server.addOutputFileArg("xdg-shell-server-protocol.h");

    const code = b.addSystemCommand(&.{ "wayland-scanner", "private-code" });
    code.addFileArg(xml);
    const private_code = code.addOutputFileArg("xdg-shell-protocol.c");

    return .{
        .client_header = client_header,
        .server_header = server_header,
        .private_code = private_code,
    };
}

fn addXdgProtocol(module: *std.Build.Module, xdg: XdgProtocol) void {
    module.addIncludePath(xdg.client_header.dirname());
    module.addIncludePath(xdg.server_header.dirname());
    module.addCSourceFile(.{
        .file = xdg.private_code,
        .flags = &.{ "-std=c99", "-Wno-unused-parameter" },
    });
}
