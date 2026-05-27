//! Delegate for wl_shm_pool. Owns the fd handoff for plugin-supplied
//! shared-memory buffers.

const std = @import("std");
const buffer_protocol = @import("buffer.zig");
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
    const buffer_bindings = buffer_protocol.Bindings(Server, ResourceData);

    return struct {
        pub const impl = wls.c.struct_wl_shm_pool_interface{
            .create_buffer = shmPoolCreateBuffer,
            .destroy = shmPoolDestroy,
            .resize = shmPoolResize,
        };

        fn shmPoolCreateBuffer(client: ?*wls.wl_client, resource: ?*wls.wl_resource, id: u32, offset: i32, width: i32, height: i32, stride: i32, format: u32) callconv(.c) void {
            const data = H.dataForResource(resource) orelse return;
            const pool = H.resourceProxyAs(wlp.wl_shm_pool, resource) orelse return;
            const buffer = wlc.c.wl_shm_pool_create_buffer(pool, offset, width, height, stride, format) orelse return;
            const wl_client = client orelse return;
            const buffer_resource = data.server.createResource(
                wl_client,
                .buffer,
                &wls.c.wl_buffer_interface,
                1,
                id,
                @ptrCast(&buffer_bindings.impl),
                @ptrCast(buffer),
            ) orelse return;
            const buffer_data = H.dataForResource(buffer_resource) orelse return;
            _ = wlc.c.wl_buffer_add_listener(buffer, &buffer_bindings.listener, buffer_data);
        }

        fn shmPoolDestroy(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            if (H.dataForResource(resource)) |data| {
                if (H.proxyAs(wlp.wl_shm_pool, data.upstream_proxy)) |pool| {
                    wlc.c.wl_shm_pool_destroy(pool);
                    data.upstream_proxy = null;
                }
            }
            H.resourceRelease(null, resource);
        }

        fn shmPoolResize(_: ?*wls.wl_client, resource: ?*wls.wl_resource, size: i32) callconv(.c) void {
            const pool = H.resourceProxyAs(wlp.wl_shm_pool, resource) orelse return;
            wlc.c.wl_shm_pool_resize(pool, size);
        }
    };
}

test "compiles" {
    _ = create();
}
