//! Passive records, ids, enums, and flags for the wayembed model.
//!
//! No methods, no protocol behavior, no cross-table mutation. Per
//! docs/dod.md § Core Rule. New record types added here are picked up
//! automatically by data/snapshot.zig and data/invariants.zig.

const std = @import("std");
const wlc = @import("../wayland/client.zig");
const wls = @import("../wayland/server.zig");

// ===== Logical ids =====

pub const ClientId = enum(u32) { null_id = 0, _ };
pub const ResourceId = enum(u32) { null_id = 0, _ };
pub const SurfaceId = enum(u32) { null_id = 0, _ };
pub const BufferId = enum(u32) { null_id = 0, _ };
pub const EmbedId = enum(u32) { null_id = 0, _ };
pub const OutputId = enum(u32) { null_id = 0, _ };

// ===== Lifecycle states =====

pub const ServerState = enum {
    stopped,
    running,
    shutting_down,
};

pub const ClientState = enum {
    connected,
    closing,
    dead,
};

pub const ResourceState = enum {
    alive,
    destroying,
    dead,
};

pub const EmbedState = enum {
    reserved,
    parent_ready,
    child_ready,
    mapped,
    destroyed,
};

pub const SurfaceRole = enum {
    none,
    toplevel,
    popup,
    subsurface,
    cursor,
};

pub const ResourceKind = enum {
    compositor,
    subcompositor,
    surface,
    subsurface,
    region,
    shm,
    shm_pool,
    buffer,
    callback,
    seat,
    pointer,
    keyboard,
    touch,
    output,
    xdg_wm_base,
    xdg_positioner,
    xdg_surface,
    xdg_toplevel,
    xdg_popup,
    registry,
    other,
};

// ===== Records =====

pub const Client = struct {
    id: ClientId,
    state: ClientState,
    server_fd: i32,
    client_fd: i32,
    wl_client: ?*wls.wl_client,
    wl_display: ?*wlc.wl_display,
};

pub const Resource = struct {
    id: ResourceId,
    client_id: ClientId,
    kind: ResourceKind,
    state: ResourceState,
    wl_resource: ?*wls.wl_resource,
    upstream_proxy: ?*wlc.wl_proxy,
    generation: u32,
};

pub const Surface = struct {
    id: SurfaceId,
    client_id: ClientId,
    resource_id: ResourceId,
    role: SurfaceRole,
};

pub const Buffer = struct {
    id: BufferId,
    client_id: ClientId,
    resource_id: ResourceId,
};

pub const Embed = struct {
    id: EmbedId,
    client_id: ClientId,
    state: EmbedState,
    host_parent_surface_id: SurfaceId,
    plugin_child_surface_id: SurfaceId,
    subsurface_resource_id: ResourceId,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

pub const Output = struct {
    id: OutputId,
    resource_id: ResourceId,
    name: u32,
};

// ===== Counters =====

pub const IdCounters = struct {
    client: u32 = 0,
    resource: u32 = 0,
    surface: u32 = 0,
    buffer: u32 = 0,
    embed: u32 = 0,
    output: u32 = 0,
};

// ===== production code above =====

test "id null is zero" {
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(ClientId.null_id));
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(EmbedId.null_id));
}

test "Embed record default-constructs" {
    const e: Embed = .{
        .id = .null_id,
        .client_id = .null_id,
        .state = .reserved,
        .host_parent_surface_id = .null_id,
        .plugin_child_surface_id = .null_id,
        .subsurface_resource_id = .null_id,
        .x = 0,
        .y = 0,
        .width = 0,
        .height = 0,
    };
    try std.testing.expect(e.state == .reserved);
}
