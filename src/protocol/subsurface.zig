//! Delegate for wl_subsurface. Owns positioning forwarding for the
//! embedded child surface.

const std = @import("std");
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

    return struct {
        pub const impl = wls.c.struct_wl_subsurface_interface{
            .destroy = subsurfaceDestroy,
            .set_position = subsurfaceSetPosition,
            .place_above = subsurfacePlaceAbove,
            .place_below = subsurfacePlaceBelow,
            .set_sync = subsurfaceSetSync,
            .set_desync = subsurfaceSetDesync,
        };

        fn subsurfaceDestroy(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            if (H.dataForResource(resource)) |data| {
                if (H.proxyAs(wlp.wl_subsurface, data.upstream_proxy)) |subsurface| {
                    wlc.c.wl_subsurface_destroy(subsurface);
                    data.upstream_proxy = null;
                }
            }
            H.resourceRelease(null, resource);
        }

        fn subsurfaceSetPosition(_: ?*wls.wl_client, resource: ?*wls.wl_resource, x: i32, y: i32) callconv(.c) void {
            const subsurface = H.resourceProxyAs(wlp.wl_subsurface, resource) orelse return;
            wlc.c.wl_subsurface_set_position(subsurface, x, y);
        }

        fn subsurfacePlaceAbove(_: ?*wls.wl_client, resource: ?*wls.wl_resource, sibling_resource: ?*wls.wl_resource) callconv(.c) void {
            const subsurface = H.resourceProxyAs(wlp.wl_subsurface, resource) orelse return;
            const sibling = H.resourceProxyAs(wlp.wl_surface, sibling_resource) orelse return;
            wlc.c.wl_subsurface_place_above(subsurface, sibling);
        }

        fn subsurfacePlaceBelow(_: ?*wls.wl_client, resource: ?*wls.wl_resource, sibling_resource: ?*wls.wl_resource) callconv(.c) void {
            const subsurface = H.resourceProxyAs(wlp.wl_subsurface, resource) orelse return;
            const sibling = H.resourceProxyAs(wlp.wl_surface, sibling_resource) orelse return;
            wlc.c.wl_subsurface_place_below(subsurface, sibling);
        }

        fn subsurfaceSetSync(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            const subsurface = H.resourceProxyAs(wlp.wl_subsurface, resource) orelse return;
            wlc.c.wl_subsurface_set_sync(subsurface);
        }

        fn subsurfaceSetDesync(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            const subsurface = H.resourceProxyAs(wlp.wl_subsurface, resource) orelse return;
            wlc.c.wl_subsurface_set_desync(subsurface);
        }
    };
}

test "compiles" {
    _ = create();
}
