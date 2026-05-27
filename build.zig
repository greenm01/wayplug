const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const xdg = xdgProtocol(b);

    const wayembed_mod = b.addModule("wayembed", .{
        .root_source_file = b.path("src/wayembed.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    linkWayland(wayembed_mod);
    addXdgProtocol(wayembed_mod, xdg);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "wayembed",
        .root_module = wayembed_mod,
    });
    lib.installHeader(b.path("include/wayembed.h"), "wayembed.h");
    lib.installHeader(b.path("include/wayembed_adapters.h"), "wayembed_adapters.h");
    b.installArtifact(lib);

    const test_step = b.step("test", "Run unit and C ABI smoke tests");
    var previous_test_run: ?*std.Build.Step = null;

    // Unit tests: drive the in-file `test` blocks under src/.
    const unit_test_mod = b.createModule(.{
        .root_source_file = b.path("src/wayembed.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    linkWayland(unit_test_mod);
    addXdgProtocol(unit_test_mod, xdg);
    const unit_tests = b.addTest(.{
        .root_module = unit_test_mod,
    });
    const unit_run = b.addRunArtifact(unit_tests);
    removeSmokeEnvironment(unit_run);
    if (previous_test_run) |previous| unit_run.step.dependOn(previous);
    previous_test_run = &unit_run.step;
    test_step.dependOn(&unit_run.step);

    // Integration tests: each file imports the `wayembed` module.
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
        mod.addImport("wayembed", wayembed_mod);
        linkWayland(mod);
        const t = b.addTest(.{ .root_module = mod });
        const run = b.addRunArtifact(t);
        if (!std.mem.eql(u8, path, "tests/protocol_smoke_tests.zig")) {
            removeSmokeEnvironment(run);
        }
        if (previous_test_run) |previous| run.step.dependOn(previous);
        previous_test_run = &run.step;
        test_step.dependOn(&run.step);
    }

    // C ABI smoke: compile c_abi_smoke.c against the static lib.
    const c_abi_smoke = b.addExecutable(.{
        .name = "wayembed-c-abi-smoke",
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
    const c_abi_run = b.addRunArtifact(c_abi_smoke);
    removeSmokeEnvironment(c_abi_run);
    if (previous_test_run) |previous| c_abi_run.step.dependOn(previous);
    previous_test_run = &c_abi_run.step;
    test_step.dependOn(&c_abi_run.step);
}

fn removeSmokeEnvironment(run: *std.Build.Step.Run) void {
    run.removeEnvironmentVariable("WAYEMBED_SMOKE_COMPOSITOR");
    run.removeEnvironmentVariable("WAYEMBED_RIVER_BIN");
    run.removeEnvironmentVariable("WAYEMBED_MUTTER_BIN");
    run.removeEnvironmentVariable("WAYEMBED_NIRI_BIN");
    run.removeEnvironmentVariable("WAYEMBED_KWIN_BIN");
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
