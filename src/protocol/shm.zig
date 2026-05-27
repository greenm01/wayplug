//! Delegate for wl_shm. Forwards format advertisements from the host
//! and creates shm pools on bind.

const std = @import("std");
const runtime = @import("runtime.zig");
const shm_pool_protocol = @import("shm_pool.zig");
const wlc = @import("../wayland/client.zig");
const wlp = @import("../wayland/protocols.zig");
const wls = @import("../wayland/server.zig");

const sys = @cImport({
    @cInclude("unistd.h");
});

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

pub fn Bindings(comptime Server: type, comptime ResourceData: type) type {
    const H = runtime.Helpers(Server, ResourceData);
    const shm_pool_bindings = shm_pool_protocol.Bindings(Server, ResourceData);

    return struct {
        pub const impl = wls.c.struct_wl_shm_interface{
            .create_pool = shmCreatePool,
            .release = H.resourceRelease,
        };

        fn shmCreatePool(client: ?*wls.wl_client, resource: ?*wls.wl_resource, id: u32, fd: i32, size: i32) callconv(.c) void {
            const data = H.dataForResource(resource) orelse {
                _ = sys.close(fd);
                return;
            };
            const shm = H.resourceProxyAs(wlp.wl_shm, resource) orelse {
                _ = sys.close(fd);
                return;
            };
            const pool = wlc.c.wl_shm_create_pool(shm, fd, size) orelse {
                _ = sys.close(fd);
                return;
            };
            _ = sys.close(fd);
            const wl_client = client orelse return;
            _ = data.server.createResource(
                wl_client,
                .shm_pool,
                &wls.c.wl_shm_pool_interface,
                1,
                id,
                @ptrCast(&shm_pool_bindings.impl),
                @ptrCast(pool),
            );
        }
    };
}

test "compiles" {
    _ = create();
}
