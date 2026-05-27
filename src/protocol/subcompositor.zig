//! Delegate for wl_subcompositor. Creates wl_subsurface resources and
//! triggers embedAttachChild on the engine.

const std = @import("std");
const runtime = @import("runtime.zig");
const subsurface_protocol = @import("subsurface.zig");
const wlc = @import("../wayland/client.zig");
const wlp = @import("../wayland/protocols.zig");
const wls = @import("../wayland/server.zig");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

pub fn Bindings(comptime Server: type, comptime ResourceData: type) type {
    const H = runtime.Helpers(Server, ResourceData);
    const subsurface_bindings = subsurface_protocol.Bindings(Server, ResourceData);

    return struct {
        pub const impl = wls.c.struct_wl_subcompositor_interface{
            .destroy = H.resourceRelease,
            .get_subsurface = subcompositorGetSubsurface,
        };

        fn subcompositorGetSubsurface(client: ?*wls.wl_client, resource: ?*wls.wl_resource, id: u32, surface_resource: ?*wls.wl_resource, parent_resource: ?*wls.wl_resource) callconv(.c) void {
            const data = H.dataForResource(resource) orelse return;
            const subcompositor = H.resourceProxyAs(wlp.wl_subcompositor, resource) orelse return;
            const surface = H.resourceProxyAs(wlp.wl_surface, surface_resource) orelse return;
            const parent = H.resourceProxyAs(wlp.wl_surface, parent_resource) orelse return;
            const subsurface = wlc.c.wl_subcompositor_get_subsurface(subcompositor, surface, parent) orelse return;
            const wl_client = client orelse return;
            _ = data.server.createResource(
                wl_client,
                .subsurface,
                &wls.c.wl_subsurface_interface,
                1,
                id,
                @ptrCast(&subsurface_bindings.impl),
                @ptrCast(subsurface),
            );
        }
    };
}

test "compiles" {
    _ = create();
}
