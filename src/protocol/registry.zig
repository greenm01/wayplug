//! wl_registry bind dispatch. Advertises only the globals the host
//! supplies through `wayplug_host_interface`.

const std = @import("std");
const compositor_protocol = @import("compositor.zig");
const runtime = @import("runtime.zig");
const shm_protocol = @import("shm.zig");
const subcompositor_protocol = @import("subcompositor.zig");
const wls = @import("../wayland/server.zig");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

pub fn selectVersion(requested: u32, advertised_max: u32) ?u32 {
    if (requested == 0 or requested > advertised_max) return null;
    return requested;
}

pub fn Bindings(comptime Server: type, comptime ResourceData: type) type {
    const H = runtime.Helpers(Server, ResourceData);
    const compositor_bindings = compositor_protocol.Bindings(Server, ResourceData);
    const shm_bindings = shm_protocol.Bindings(Server, ResourceData);
    const subcompositor_bindings = subcompositor_protocol.Bindings(Server, ResourceData);

    return struct {
        const invalid_method: u32 = @intCast(wls.c.WL_DISPLAY_ERROR_INVALID_METHOD);
        const implementation_error: u32 = @intCast(wls.c.WL_DISPLAY_ERROR_IMPLEMENTATION);

        pub fn bindCompositor(client: ?*wls.wl_client, data: ?*anyopaque, version: u32, id: u32) callconv(.c) void {
            const server = H.serverFromData(data) orelse return;
            const wl_client = client orelse return;
            const selected_version = selectVersion(version, 4) orelse {
                server.protocolErrorForClient(wl_client, invalid_method);
                return;
            };
            const compositor = server.host.getCompositor() orelse {
                server.protocolErrorForClient(wl_client, implementation_error);
                return;
            };
            _ = server.createResource(
                wl_client,
                .compositor,
                &wls.c.wl_compositor_interface,
                selected_version,
                id,
                @ptrCast(&compositor_bindings.impl),
                @ptrCast(compositor),
            );
        }

        pub fn bindSubcompositor(client: ?*wls.wl_client, data: ?*anyopaque, version: u32, id: u32) callconv(.c) void {
            const server = H.serverFromData(data) orelse return;
            const wl_client = client orelse return;
            const selected_version = selectVersion(version, 1) orelse {
                server.protocolErrorForClient(wl_client, invalid_method);
                return;
            };
            const subcompositor = server.host.getSubcompositor() orelse {
                server.protocolErrorForClient(wl_client, implementation_error);
                return;
            };
            _ = server.createResource(
                wl_client,
                .subcompositor,
                &wls.c.wl_subcompositor_interface,
                selected_version,
                id,
                @ptrCast(&subcompositor_bindings.impl),
                @ptrCast(subcompositor),
            );
        }

        pub fn bindShm(client: ?*wls.wl_client, data: ?*anyopaque, version: u32, id: u32) callconv(.c) void {
            const server = H.serverFromData(data) orelse return;
            const wl_client = client orelse return;
            const selected_version = selectVersion(version, 1) orelse {
                server.protocolErrorForClient(wl_client, invalid_method);
                return;
            };
            const shm = server.host.getShm() orelse {
                server.protocolErrorForClient(wl_client, implementation_error);
                return;
            };
            const resource = server.createResource(
                wl_client,
                .shm,
                &wls.c.wl_shm_interface,
                selected_version,
                id,
                @ptrCast(&shm_bindings.impl),
                @ptrCast(shm),
            ) orelse return;
            wls.c.wl_shm_send_format(resource, wls.c.WL_SHM_FORMAT_ARGB8888);
            wls.c.wl_shm_send_format(resource, wls.c.WL_SHM_FORMAT_XRGB8888);
        }
    };
}

test "compiles" {
    _ = create();
}

test "selectVersion accepts supported requests" {
    try std.testing.expectEqual(@as(?u32, 1), selectVersion(1, 4));
    try std.testing.expectEqual(@as(?u32, 4), selectVersion(4, 4));
}

test "selectVersion rejects invalid requests" {
    try std.testing.expectEqual(@as(?u32, null), selectVersion(0, 4));
    try std.testing.expectEqual(@as(?u32, null), selectVersion(5, 4));
}
