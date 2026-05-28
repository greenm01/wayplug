//! Delegate for xdg_surface. Owns XDG role creation and configure
//! forwarding for a wl_surface.

const std = @import("std");
const popup_protocol = @import("xdg_popup.zig");
const runtime = @import("runtime.zig");
const toplevel_protocol = @import("xdg_toplevel.zig");
const xdgc = @import("../wayland/xdg_client.zig");
const xdgs = @import("../wayland/xdg_server.zig");
const types = @import("../data/types.zig");
const wls = @import("../wayland/server.zig");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

pub fn Bindings(comptime Server: type, comptime ResourceData: type) type {
    const H = runtime.Helpers(Server, ResourceData);
    const popup_bindings = popup_protocol.Bindings(Server, ResourceData);
    const toplevel_bindings = toplevel_protocol.Bindings(Server, ResourceData);

    return struct {
        pub const impl = xdgs.c.struct_xdg_surface_interface{
            .destroy = xdgSurfaceDestroy,
            .get_toplevel = xdgSurfaceGetToplevel,
            .get_popup = xdgSurfaceGetPopup,
            .set_window_geometry = xdgSurfaceSetWindowGeometry,
            .ack_configure = xdgSurfaceAckConfigure,
        };

        pub const listener = xdgc.c.struct_xdg_surface_listener{
            .configure = xdgSurfaceConfigure,
        };

        fn xdgSurfaceDestroy(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            if (H.dataForResource(resource)) |data| {
                if (H.proxyAs(xdgc.xdg_surface, data.upstream_proxy)) |surface| {
                    xdgc.c.xdg_surface_destroy(surface);
                    data.upstream_proxy = null;
                }
            }
            H.resourceRelease(null, resource);
        }

        fn xdgSurfaceGetToplevel(client: ?*wls.wl_client, resource: ?*wls.wl_resource, id: u32) callconv(.c) void {
            const data = H.dataForResource(resource) orelse return;
            if (!assignRole(data, .toplevel)) return;
            const surface = H.resourceProxyAs(xdgc.xdg_surface, resource) orelse return;
            const toplevel = xdgc.c.xdg_surface_get_toplevel(surface) orelse return;
            const wl_client = client orelse return;
            const toplevel_resource = data.server.createResource(
                wl_client,
                .xdg_toplevel,
                &xdgs.c.xdg_toplevel_interface,
                resourceVersion(resource),
                id,
                @ptrCast(&toplevel_bindings.impl),
                @ptrCast(toplevel),
            ) orelse return;
            const toplevel_data = H.dataForResource(toplevel_resource) orelse return;
            _ = xdgc.c.xdg_toplevel_add_listener(toplevel, &toplevel_bindings.listener, toplevel_data);
        }

        fn xdgSurfaceGetPopup(client: ?*wls.wl_client, resource: ?*wls.wl_resource, id: u32, parent_resource: ?*wls.wl_resource, positioner_resource: ?*wls.wl_resource) callconv(.c) void {
            const data = H.dataForResource(resource) orelse return;
            if (!assignRole(data, .popup)) return;
            const surface = H.resourceProxyAs(xdgc.xdg_surface, resource) orelse return;
            const parent = H.resourceProxyAs(xdgc.xdg_surface, parent_resource);
            const positioner = H.resourceProxyAs(xdgc.xdg_positioner, positioner_resource) orelse return;
            const popup = xdgc.c.xdg_surface_get_popup(surface, parent, positioner) orelse return;
            const wl_client = client orelse return;
            const popup_resource = data.server.createResource(
                wl_client,
                .xdg_popup,
                &xdgs.c.xdg_popup_interface,
                resourceVersion(resource),
                id,
                @ptrCast(&popup_bindings.impl),
                @ptrCast(popup),
            ) orelse return;
            const popup_data = H.dataForResource(popup_resource) orelse return;
            _ = xdgc.c.xdg_popup_add_listener(popup, &popup_bindings.listener, popup_data);
        }

        fn xdgSurfaceSetWindowGeometry(_: ?*wls.wl_client, resource: ?*wls.wl_resource, x: i32, y: i32, width: i32, height: i32) callconv(.c) void {
            const surface = H.resourceProxyAs(xdgc.xdg_surface, resource) orelse return;
            xdgc.c.xdg_surface_set_window_geometry(surface, x, y, width, height);
        }

        fn xdgSurfaceAckConfigure(_: ?*wls.wl_client, resource: ?*wls.wl_resource, serial: u32) callconv(.c) void {
            const surface = H.resourceProxyAs(xdgc.xdg_surface, resource) orelse return;
            xdgc.c.xdg_surface_ack_configure(surface, serial);
        }

        fn xdgSurfaceConfigure(userdata: ?*anyopaque, _: ?*xdgc.xdg_surface, serial: u32) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            xdgs.c.xdg_surface_send_configure(data.wl_resource, serial);
        }

        fn assignRole(data: *ResourceData, role: types.SurfaceRole) bool {
            const surface_id = data.xdg_surface_id orelse return false;
            data.server.engine.surfaceAssignRole(surface_id, role) catch {
                postRoleError(data);
                return false;
            };
            return true;
        }

        fn postRoleError(data: *ResourceData) void {
            if (data.xdg_wm_base_resource) |wm_base| {
                xdgs.c.wl_resource_post_error(
                    wm_base,
                    xdgs.c.XDG_WM_BASE_ERROR_ROLE,
                    "wl_surface already has a role",
                );
            }
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
