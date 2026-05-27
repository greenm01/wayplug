//! Delegate for wl_surface. Owns the hot-path forwarding for
//! attach/damage/commit per docs/architecture.md § What Stays Direct.

const std = @import("std");
const callback_protocol = @import("callback.zig");
const runtime = @import("runtime.zig");
const wlc = @import("../wayland/client.zig");
const wlp = @import("../wayland/protocols.zig");
const wls = @import("../wayland/server.zig");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

pub fn Bindings(comptime Server: type, comptime ResourceData: type) type {
    const H = runtime.Helpers(Server, ResourceData);
    const callback_bindings = callback_protocol.Bindings(Server, ResourceData);

    return struct {
        pub const impl = surfaceImpl();

        fn surfaceImpl() wls.c.struct_wl_surface_interface {
            if (comptime @hasField(wls.c.struct_wl_surface_interface, "get_release")) {
                return .{
                    .destroy = surfaceDestroy,
                    .attach = surfaceAttach,
                    .damage = surfaceDamage,
                    .frame = surfaceFrame,
                    .set_opaque_region = surfaceSetOpaqueRegion,
                    .set_input_region = surfaceSetInputRegion,
                    .commit = surfaceCommit,
                    .set_buffer_transform = surfaceSetBufferTransform,
                    .set_buffer_scale = surfaceSetBufferScale,
                    .damage_buffer = surfaceDamageBuffer,
                    .offset = null,
                    .get_release = null,
                };
            }
            return .{
                .destroy = surfaceDestroy,
                .attach = surfaceAttach,
                .damage = surfaceDamage,
                .frame = surfaceFrame,
                .set_opaque_region = surfaceSetOpaqueRegion,
                .set_input_region = surfaceSetInputRegion,
                .commit = surfaceCommit,
                .set_buffer_transform = surfaceSetBufferTransform,
                .set_buffer_scale = surfaceSetBufferScale,
                .damage_buffer = surfaceDamageBuffer,
                .offset = null,
            };
        }

        fn surfaceDestroy(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            if (H.dataForResource(resource)) |data| {
                if (H.proxyAs(wlp.wl_surface, data.upstream_proxy)) |surface| {
                    wlc.c.wl_surface_destroy(surface);
                    data.upstream_proxy = null;
                }
            }
            H.resourceRelease(null, resource);
        }

        fn surfaceAttach(_: ?*wls.wl_client, resource: ?*wls.wl_resource, buffer: ?*wls.wl_resource, x: i32, y: i32) callconv(.c) void {
            const surface = H.resourceProxyAs(wlp.wl_surface, resource) orelse return;
            const upstream_buffer = H.resourceProxyAs(wlp.wl_buffer, buffer);
            wlc.c.wl_surface_attach(surface, upstream_buffer, x, y);
        }

        fn surfaceDamage(_: ?*wls.wl_client, resource: ?*wls.wl_resource, x: i32, y: i32, width: i32, height: i32) callconv(.c) void {
            const surface = H.resourceProxyAs(wlp.wl_surface, resource) orelse return;
            wlc.c.wl_surface_damage(surface, x, y, width, height);
        }

        fn surfaceFrame(client: ?*wls.wl_client, resource: ?*wls.wl_resource, id: u32) callconv(.c) void {
            const data = H.dataForResource(resource) orelse return;
            const surface = H.resourceProxyAs(wlp.wl_surface, resource) orelse return;
            const callback = wlc.c.wl_surface_frame(surface) orelse return;
            const wl_client = client orelse return;
            const callback_resource = data.server.createResource(
                wl_client,
                .callback,
                &wls.c.wl_callback_interface,
                1,
                id,
                null,
                @ptrCast(callback),
            ) orelse return;
            const callback_data = H.dataForResource(callback_resource) orelse return;
            _ = wlc.c.wl_callback_add_listener(callback, &callback_bindings.listener, callback_data);
        }

        fn surfaceSetOpaqueRegion(_: ?*wls.wl_client, resource: ?*wls.wl_resource, region: ?*wls.wl_resource) callconv(.c) void {
            const surface = H.resourceProxyAs(wlp.wl_surface, resource) orelse return;
            wlc.c.wl_surface_set_opaque_region(surface, H.resourceProxyAs(wlp.wl_region, region));
        }

        fn surfaceSetInputRegion(_: ?*wls.wl_client, resource: ?*wls.wl_resource, region: ?*wls.wl_resource) callconv(.c) void {
            const surface = H.resourceProxyAs(wlp.wl_surface, resource) orelse return;
            wlc.c.wl_surface_set_input_region(surface, H.resourceProxyAs(wlp.wl_region, region));
        }

        fn surfaceCommit(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            const surface = H.resourceProxyAs(wlp.wl_surface, resource) orelse return;
            wlc.c.wl_surface_commit(surface);
        }

        fn surfaceSetBufferTransform(_: ?*wls.wl_client, resource: ?*wls.wl_resource, transform: i32) callconv(.c) void {
            const surface = H.resourceProxyAs(wlp.wl_surface, resource) orelse return;
            wlc.c.wl_surface_set_buffer_transform(surface, transform);
        }

        fn surfaceSetBufferScale(_: ?*wls.wl_client, resource: ?*wls.wl_resource, scale: i32) callconv(.c) void {
            const surface = H.resourceProxyAs(wlp.wl_surface, resource) orelse return;
            wlc.c.wl_surface_set_buffer_scale(surface, scale);
        }

        fn surfaceDamageBuffer(_: ?*wls.wl_client, resource: ?*wls.wl_resource, x: i32, y: i32, width: i32, height: i32) callconv(.c) void {
            const surface = H.resourceProxyAs(wlp.wl_surface, resource) orelse return;
            wlc.c.wl_surface_damage_buffer(surface, x, y, width, height);
        }
    };
}

test "compiles" {
    _ = create();
}
