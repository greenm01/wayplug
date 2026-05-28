//! Delegate for xdg_wm_base. Creates XDG shell helper objects and
//! forwards compositor ping/pong.

const std = @import("std");
const positioner_protocol = @import("xdg_positioner.zig");
const runtime = @import("runtime.zig");
const surface_protocol = @import("xdg_surface.zig");
const xdgc = @import("../wayland/xdg_client.zig");
const xdgs = @import("../wayland/xdg_server.zig");
const wlp = @import("../wayland/protocols.zig");
const wls = @import("../wayland/server.zig");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

pub fn Bindings(comptime Server: type, comptime ResourceData: type) type {
    const H = runtime.Helpers(Server, ResourceData);
    const positioner_bindings = positioner_protocol.Bindings(Server, ResourceData);
    const surface_bindings = surface_protocol.Bindings(Server, ResourceData);

    return struct {
        pub const impl = xdgs.c.struct_xdg_wm_base_interface{
            .destroy = H.resourceRelease,
            .create_positioner = wmBaseCreatePositioner,
            .get_xdg_surface = wmBaseGetXdgSurface,
            .pong = wmBasePong,
        };

        pub const listener = xdgc.c.struct_xdg_wm_base_listener{
            .ping = wmBasePing,
        };

        fn wmBaseCreatePositioner(client: ?*wls.wl_client, resource: ?*wls.wl_resource, id: u32) callconv(.c) void {
            const data = H.dataForResource(resource) orelse return;
            const wm_base = H.resourceProxyAs(xdgc.xdg_wm_base, resource) orelse return;
            const positioner = xdgc.c.xdg_wm_base_create_positioner(wm_base) orelse return;
            const wl_client = client orelse return;
            _ = data.server.createResource(
                wl_client,
                .xdg_positioner,
                &xdgs.c.xdg_positioner_interface,
                resourceVersion(resource),
                id,
                @ptrCast(&positioner_bindings.impl),
                @ptrCast(positioner),
            );
        }

        fn wmBaseGetXdgSurface(client: ?*wls.wl_client, resource: ?*wls.wl_resource, id: u32, surface_resource: ?*wls.wl_resource) callconv(.c) void {
            const data = H.dataForResource(resource) orelse return;
            const surface_data = H.dataForResource(surface_resource) orelse return;
            const surface_id = data.server.engine.surfaceForResource(surface_data.resource_id) orelse return;
            if (data.server.engine.surfaceRole(surface_id)) |role| {
                if (role != .none) {
                    postRoleError(data);
                    return;
                }
            }
            const wm_base = H.resourceProxyAs(xdgc.xdg_wm_base, resource) orelse return;
            const surface = H.resourceProxyAs(wlp.wl_surface, surface_resource) orelse return;
            const xdg_surface = xdgc.c.xdg_wm_base_get_xdg_surface(wm_base, surface) orelse return;
            const wl_client = client orelse return;
            const xdg_resource = data.server.createResource(
                wl_client,
                .xdg_surface,
                &xdgs.c.xdg_surface_interface,
                resourceVersion(resource),
                id,
                @ptrCast(&surface_bindings.impl),
                @ptrCast(xdg_surface),
            ) orelse return;
            const xdg_data = H.dataForResource(xdg_resource) orelse return;
            xdg_data.xdg_wm_base_resource = data.wl_resource;
            xdg_data.xdg_surface_id = surface_id;
            _ = xdgc.c.xdg_surface_add_listener(xdg_surface, &surface_bindings.listener, xdg_data);
        }

        fn wmBasePong(_: ?*wls.wl_client, resource: ?*wls.wl_resource, serial: u32) callconv(.c) void {
            const wm_base = H.resourceProxyAs(xdgc.xdg_wm_base, resource) orelse return;
            xdgc.c.xdg_wm_base_pong(wm_base, serial);
        }

        fn wmBasePing(userdata: ?*anyopaque, _: ?*xdgc.xdg_wm_base, serial: u32) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            xdgs.c.xdg_wm_base_send_ping(data.wl_resource, serial);
        }

        fn postRoleError(data: *ResourceData) void {
            xdgs.c.wl_resource_post_error(
                data.wl_resource,
                xdgs.c.XDG_WM_BASE_ERROR_ROLE,
                "wl_surface already has a role",
            );
            data.server.fatalProtocolError(data.client_id, @intCast(xdgs.c.XDG_WM_BASE_ERROR_ROLE));
        }

        fn dataFromListener(userdata: ?*anyopaque) ?*ResourceData {
            const ptr = userdata orelse return null;
            return @ptrCast(@alignCast(ptr));
        }

        fn resourceVersion(resource: ?*wls.wl_resource) u32 {
            const r = resource orelse return 1;
            return @intCast(wls.c.wl_resource_get_version(r));
        }
    };
}

test "compiles" {
    _ = create();
}
