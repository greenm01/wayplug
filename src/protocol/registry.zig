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

pub fn Bindings(comptime Server: type, comptime ResourceData: type) type {
    const H = runtime.Helpers(Server, ResourceData);
    const compositor_bindings = compositor_protocol.Bindings(Server, ResourceData);
    const shm_bindings = shm_protocol.Bindings(Server, ResourceData);
    const subcompositor_bindings = subcompositor_protocol.Bindings(Server, ResourceData);

    return struct {
        pub fn bindCompositor(client: ?*wls.wl_client, data: ?*anyopaque, version: u32, id: u32) callconv(.c) void {
            const server = H.serverFromData(data) orelse return;
            const wl_client = client orelse return;
            const compositor = server.host.getCompositor() orelse return;
            _ = server.createResource(
                wl_client,
                .compositor,
                &wls.c.wl_compositor_interface,
                @min(version, 4),
                id,
                @ptrCast(&compositor_bindings.impl),
                @ptrCast(compositor),
            );
        }

        pub fn bindSubcompositor(client: ?*wls.wl_client, data: ?*anyopaque, version: u32, id: u32) callconv(.c) void {
            const server = H.serverFromData(data) orelse return;
            const wl_client = client orelse return;
            const subcompositor = server.host.getSubcompositor() orelse return;
            _ = server.createResource(
                wl_client,
                .subcompositor,
                &wls.c.wl_subcompositor_interface,
                @min(version, 1),
                id,
                @ptrCast(&subcompositor_bindings.impl),
                @ptrCast(subcompositor),
            );
        }

        pub fn bindShm(client: ?*wls.wl_client, data: ?*anyopaque, version: u32, id: u32) callconv(.c) void {
            const server = H.serverFromData(data) orelse return;
            const wl_client = client orelse return;
            const shm = server.host.getShm() orelse return;
            const resource = server.createResource(
                wl_client,
                .shm,
                &wls.c.wl_shm_interface,
                @min(version, 1),
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
