//! Delegate for wl_compositor.

const std = @import("std");
const region_protocol = @import("region.zig");
const runtime = @import("runtime.zig");
const surface_protocol = @import("surface.zig");
const wlc = @import("../wayland/client.zig");
const wlp = @import("../wayland/protocols.zig");
const wls = @import("../wayland/server.zig");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

pub fn Bindings(comptime Server: type, comptime ResourceData: type) type {
    const H = runtime.Helpers(Server, ResourceData);
    const region_bindings = region_protocol.Bindings(Server, ResourceData);
    const surface_bindings = surface_protocol.Bindings(Server, ResourceData);

    return struct {
        pub const impl = wls.c.struct_wl_compositor_interface{
            .create_surface = compositorCreateSurface,
            .create_region = compositorCreateRegion,
            .release = H.resourceRelease,
        };

        fn compositorCreateSurface(client: ?*wls.wl_client, resource: ?*wls.wl_resource, id: u32) callconv(.c) void {
            const data = H.dataForResource(resource) orelse return;
            const compositor = H.resourceProxyAs(wlp.wl_compositor, resource) orelse return;
            const surface = wlc.c.wl_compositor_create_surface(compositor) orelse return;
            const wl_client = client orelse return;
            const surface_resource = data.server.createResource(
                wl_client,
                .surface,
                &wls.c.wl_surface_interface,
                4,
                id,
                @ptrCast(&surface_bindings.impl),
                @ptrCast(surface),
            ) orelse return;
            const surface_data = H.dataForResource(surface_resource) orelse return;
            _ = data.server.engine.surfaceCreate(data.client_id, surface_data.resource_id) catch {
                wls.c.wl_resource_destroy(surface_resource);
                return;
            };
        }

        fn compositorCreateRegion(client: ?*wls.wl_client, resource: ?*wls.wl_resource, id: u32) callconv(.c) void {
            const server_data = H.dataForResource(resource) orelse return;
            const compositor = H.resourceProxyAs(wlp.wl_compositor, resource) orelse return;
            const region = wlc.c.wl_compositor_create_region(compositor) orelse return;
            const wl_client = client orelse return;
            _ = server_data.server.createResource(
                wl_client,
                .region,
                &wls.c.wl_region_interface,
                1,
                id,
                @ptrCast(&region_bindings.impl),
                @ptrCast(region),
            );
        }
    };
}

test "compiles" {
    _ = create();
}
