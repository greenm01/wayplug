//! Internal server runtime behind the opaque `wayplug_server` handle.
//! Owns the engine, the host wrapper, and the upstream event queue.

const std = @import("std");
const c_api = @import("c_api.zig");
const engine_mod = @import("engine/engine.zig");
const host_mod = @import("host.zig");
const wlc = @import("wayland/client.zig");

pub const Server = struct {
    allocator: std.mem.Allocator,
    engine: engine_mod.Engine,
    host: host_mod.Host,
    queue: ?*wlc.wl_event_queue,

    pub fn create(
        allocator: std.mem.Allocator,
        iface: *const c_api.WayplugHostInterface,
        queue: ?*wlc.wl_event_queue,
    ) !*Server {
        const s = try allocator.create(Server);
        s.* = .{
            .allocator = allocator,
            .engine = engine_mod.Engine.init(allocator),
            .host = host_mod.Host.init(iface),
            .queue = queue,
        };
        return s;
    }

    pub fn destroy(self: *Server) void {
        self.engine.deinit();
        const allocator = self.allocator;
        allocator.destroy(self);
    }

    pub fn getFd(self: *Server) c_int {
        _ = self;
        return -1; // stub: no real wl_display yet
    }

    pub fn dispatch(self: *Server) void {
        _ = self;
        // stub: drain effects after real dispatch lands
    }

    pub fn flush(self: *Server) void {
        _ = self;
    }
};

// ===== production code above =====

test "Server create and destroy is balanced" {
    const iface = c_api.WayplugHostInterface{
        .size = @sizeOf(c_api.WayplugHostInterface),
        .version = c_api.abi_version,
        .userdata = null,
        .get_compositor = null,
        .get_subcompositor = null,
        .get_shm = null,
        .get_seat = null,
        .get_xdg_wm_base = null,
        .get_dmabuf = null,
        .get_subsurface_offset = null,
        .on_client_connected = null,
        .on_surface_created = null,
        .on_client_closed = null,
    };
    const s = try Server.create(std.testing.allocator, &iface, null);
    defer s.destroy();
    try std.testing.expect(s.getFd() == -1);
}
