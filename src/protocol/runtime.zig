//! Shared helpers for protocol delegates.

const wlc = @import("../wayland/client.zig");
const wls = @import("../wayland/server.zig");

pub fn Helpers(comptime Server: type, comptime ResourceData: type) type {
    return struct {
        pub fn serverFromData(data: ?*anyopaque) ?*Server {
            const ptr = data orelse return null;
            return @ptrCast(@alignCast(ptr));
        }

        pub fn dataForResource(resource: ?*wls.wl_resource) ?*ResourceData {
            const r = resource orelse return null;
            const ptr = wls.c.wl_resource_get_user_data(r) orelse return null;
            return @ptrCast(@alignCast(ptr));
        }

        pub fn proxyAs(comptime T: type, proxy: ?*wlc.wl_proxy) ?*T {
            return if (proxy) |p| @ptrCast(p) else null;
        }

        pub fn resourceProxyAs(comptime T: type, resource: ?*wls.wl_resource) ?*T {
            const data = dataForResource(resource) orelse return null;
            return proxyAs(T, data.upstream_proxy);
        }

        pub fn resourceDestroyCallback(resource: ?*wls.wl_resource) callconv(.c) void {
            const data = dataForResource(resource) orelse return;
            data.server.engine.resourceDestroy(data.resource_id);
            if (@hasDecl(ResourceData, "deinit")) data.deinit(data.server.allocator);
            data.server.allocator.destroy(data);
        }

        pub fn resourceRelease(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            if (resource) |r| wls.c.wl_resource_destroy(r);
        }
    };
}
