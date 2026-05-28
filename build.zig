const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const protocols_dir = b.option(
        []const u8,
        "wayland-protocols-dir",
        "Directory containing stable Wayland protocol XML files",
    ) orelse "/usr/share/wayland-protocols";
    const xdg = xdgProtocol(b, protocols_dir);
    const dmabuf = linuxDmabufProtocol(b, protocols_dir);

    const wayembed_mod = b.addModule("wayembed", .{
        .root_source_file = b.path("src/wayembed.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    linkWayland(wayembed_mod);
    addXdgProtocol(wayembed_mod, xdg);
    addLinuxDmabufProtocol(wayembed_mod, dmabuf);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "wayembed",
        .root_module = wayembed_mod,
    });
    lib.installHeader(b.path("include/wayembed.h"), "wayembed.h");
    lib.installHeader(b.path("include/wayembed_adapters.h"), "wayembed_adapters.h");
    b.installArtifact(lib);

    const fuzz_harness_mod = b.addModule("fuzz_harness", .{
        .root_source_file = b.path("tests/fuzz_harness.zig"),
        .target = target,
        .optimize = optimize,
    });
    fuzz_harness_mod.addImport("wayembed", wayembed_mod);

    const fuzz_lifecycle_mod = b.createModule(.{
        .root_source_file = b.path("tools/fuzz_lifecycle.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    fuzz_lifecycle_mod.addImport("fuzz_harness", fuzz_harness_mod);
    fuzz_lifecycle_mod.addImport("wayembed", wayembed_mod);
    linkWayland(fuzz_lifecycle_mod);
    const fuzz_lifecycle = b.addExecutable(.{
        .name = "wayembed-fuzz-lifecycle",
        .root_module = fuzz_lifecycle_mod,
    });
    b.installArtifact(fuzz_lifecycle);
    const fuzz_lifecycle_run = b.addRunArtifact(fuzz_lifecycle);
    removeSmokeEnvironment(fuzz_lifecycle_run);
    if (b.args) |args| fuzz_lifecycle_run.addArgs(args);
    const fuzz_lifecycle_step = b.step("fuzz-lifecycle", "Run deterministic lifecycle fuzz harness");
    fuzz_lifecycle_step.dependOn(&fuzz_lifecycle_run.step);

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
    addLinuxDmabufProtocol(unit_test_mod, dmabuf);
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
        "tests/fuzz_tests.zig",
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
        if (std.mem.eql(u8, path, "tests/fuzz_tests.zig")) {
            mod.addImport("fuzz_harness", fuzz_harness_mod);
        }
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

const LinuxDmabufProtocol = struct {
    client_header: std.Build.LazyPath,
    server_header: std.Build.LazyPath,
    private_code: std.Build.LazyPath,
};

fn linkWayland(module: *std.Build.Module) void {
    module.linkSystemLibrary("wayland-server", .{ .use_pkg_config = .yes });
    module.linkSystemLibrary("wayland-client", .{ .use_pkg_config = .yes });
}

fn xdgProtocol(b: *std.Build, protocols_dir: []const u8) XdgProtocol {
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

fn linuxDmabufProtocol(b: *std.Build, protocols_dir: []const u8) LinuxDmabufProtocol {
    const xml = std.Build.LazyPath{
        .cwd_relative = b.fmt("{s}/stable/linux-dmabuf/linux-dmabuf-v1.xml", .{protocols_dir}),
    };

    const client = b.addSystemCommand(&.{ "wayland-scanner", "client-header" });
    client.addFileArg(xml);
    const client_header = client.addOutputFileArg("linux-dmabuf-client-protocol.h");

    const server = b.addSystemCommand(&.{ "wayland-scanner", "server-header" });
    server.addFileArg(xml);
    const server_header = server.addOutputFileArg("linux-dmabuf-server-protocol.h");

    const code = b.addSystemCommand(&.{ "wayland-scanner", "private-code" });
    code.addFileArg(xml);
    const private_code = code.addOutputFileArg("linux-dmabuf-protocol.c");

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

fn addLinuxDmabufProtocol(module: *std.Build.Module, dmabuf: LinuxDmabufProtocol) void {
    module.addIncludePath(dmabuf.client_header.dirname());
    module.addIncludePath(dmabuf.server_header.dirname());
    module.addCSourceFile(.{
        .file = dmabuf.private_code,
        .flags = &.{ "-std=c99", "-Wno-unused-parameter" },
    });
}
