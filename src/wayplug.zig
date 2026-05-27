//! Root module. Aggregates submodules so the static library has a
//! single `root_source_file` and integration tests under `tests/` can
//! `@import("wayplug")` to reach the layers.

const std = @import("std");

pub const c_api = @import("c_api.zig");
pub const server = @import("server.zig");
pub const host = @import("host.zig");
pub const errors = @import("errors.zig");

pub const data = struct {
    pub const types = @import("data/types.zig");
    pub const model = @import("data/model.zig");
    pub const snapshot = @import("data/snapshot.zig");
    pub const invariants = @import("data/invariants.zig");
};

pub const engine = @import("engine/engine.zig");

pub const protocol = struct {
    pub const runtime = @import("protocol/runtime.zig");
    pub const server_display = @import("protocol/server_display.zig");
    pub const registry = @import("protocol/registry.zig");
    pub const compositor = @import("protocol/compositor.zig");
    pub const surface = @import("protocol/surface.zig");
    pub const subcompositor = @import("protocol/subcompositor.zig");
    pub const subsurface = @import("protocol/subsurface.zig");
    pub const shm = @import("protocol/shm.zig");
    pub const shm_pool = @import("protocol/shm_pool.zig");
    pub const buffer = @import("protocol/buffer.zig");
    pub const callback = @import("protocol/callback.zig");
    pub const region = @import("protocol/region.zig");
    pub const seat = @import("protocol/seat.zig");
    pub const pointer = @import("protocol/pointer.zig");
    pub const keyboard = @import("protocol/keyboard.zig");
    pub const touch = @import("protocol/touch.zig");
    pub const output = @import("protocol/output.zig");
    pub const xdg_wm_base = @import("protocol/xdg_wm_base.zig");
    pub const xdg_positioner = @import("protocol/xdg_positioner.zig");
    pub const xdg_surface = @import("protocol/xdg_surface.zig");
    pub const xdg_toplevel = @import("protocol/xdg_toplevel.zig");
    pub const xdg_popup = @import("protocol/xdg_popup.zig");
};

pub const wayland = struct {
    pub const client = @import("wayland/client.zig");
    pub const server = @import("wayland/server.zig");
    pub const protocols = @import("wayland/protocols.zig");
    pub const xdg_client = @import("wayland/xdg_client.zig");
    pub const xdg_server = @import("wayland/xdg_server.zig");
};

comptime {
    // Force every submodule to be analyzed so the static library emits
    // every `export fn` in c_api.zig regardless of which Zig code paths
    // reference them.
    _ = c_api;
    _ = server;
    _ = host;
    _ = errors;
    _ = data;
    _ = engine;
    _ = protocol;
    _ = wayland;
}

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(data);
    std.testing.refAllDecls(engine);
    std.testing.refAllDecls(protocol);
    std.testing.refAllDecls(wayland);
}
