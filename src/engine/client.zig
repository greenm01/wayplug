//! Client lifecycle: ops, queries, and policy.
//!
//! Per docs/dod.md § Operations and § Systems. Mutation and policy
//! live together per domain; the boundary lives in function naming
//! rather than in the directory tree.

const std = @import("std");
const types = @import("../data/types.zig");
const model_mod = @import("../data/model.zig");
const buffer = @import("buffer.zig");
const embed = @import("embed.zig");
const output = @import("output.zig");
const resource = @import("resource.zig");
const surface = @import("surface.zig");
const wlc = @import("../wayland/client.zig");
const wls = @import("../wayland/server.zig");
const errors = @import("../errors.zig");

// ===== Ops =====

pub fn clientCreate(
    m: *model_mod.Model,
    server_fd: i32,
    client_fd: i32,
) !types.ClientId {
    const id = try m.nextClientId();
    try m.clients.insert(m.allocator, id, .{
        .id = id,
        .state = .connected,
        .server_fd = server_fd,
        .client_fd = client_fd,
        .wl_client = null,
        .wl_display = null,
    });
    return id;
}

pub fn clientSetWlClient(
    m: *model_mod.Model,
    id: types.ClientId,
    wl_client: *wls.wl_client,
) !void {
    const c = m.clients.getMutable(id) orelse return error.UnknownClient;
    c.wl_client = wl_client;
    try m.client_by_wl_client.put(m.allocator, wl_client, id);
}

pub fn clientSetDisplay(
    m: *model_mod.Model,
    id: types.ClientId,
    display: *wlc.wl_display,
) !void {
    const c = m.clients.getMutable(id) orelse return error.UnknownClient;
    c.wl_display = display;
    try m.client_by_display.put(m.allocator, display, id);
}

pub fn clientSetWaylandHandles(
    m: *model_mod.Model,
    id: types.ClientId,
    wl_client: *wls.wl_client,
    display: *wlc.wl_display,
) !void {
    try clientSetWlClient(m, id, wl_client);
    try clientSetDisplay(m, id, display);
}

pub fn clientDestroy(m: *model_mod.Model, id: types.ClientId) void {
    const c = m.clients.getMutable(id) orelse return;
    c.state = .closing;

    while (findOwnedEmbed(m, id)) |embed_id| embed.embedDestroy(m, embed_id);
    while (findOwnedSurface(m, id)) |surface_id| surface.surfaceDestroy(m, surface_id);
    while (findOwnedBuffer(m, id)) |buffer_id| buffer.bufferDestroy(m, buffer_id);
    while (findOwnedOutput(m, id)) |output_id| output.outputDestroy(m, output_id);
    while (findOwnedResource(m, id)) |resource_id| resource.resourceDestroy(m, resource_id);

    if (c.wl_client) |wl_client| _ = m.client_by_wl_client.swapRemove(wl_client);
    if (c.wl_display) |display| _ = m.client_by_display.swapRemove(display);
    c.state = .dead;
    _ = m.clients.delete(id);
}

fn findOwnedEmbed(m: *const model_mod.Model, client_id: types.ClientId) ?types.EmbedId {
    for (m.embeds.items()) |record| {
        if (record.client_id == client_id) return record.id;
    }
    return null;
}

fn findOwnedSurface(m: *const model_mod.Model, client_id: types.ClientId) ?types.SurfaceId {
    for (m.surfaces.items()) |record| {
        if (record.client_id == client_id) return record.id;
    }
    return null;
}

fn findOwnedBuffer(m: *const model_mod.Model, client_id: types.ClientId) ?types.BufferId {
    for (m.buffers.items()) |record| {
        if (record.client_id == client_id) return record.id;
    }
    return null;
}

fn findOwnedOutput(m: *const model_mod.Model, client_id: types.ClientId) ?types.OutputId {
    for (m.outputs.items()) |record| {
        const resource_record = m.resources.get(record.resource_id) orelse continue;
        if (resource_record.client_id == client_id) return record.id;
    }
    return null;
}

fn findOwnedResource(m: *const model_mod.Model, client_id: types.ClientId) ?types.ResourceId {
    for (m.resources.items()) |record| {
        if (record.client_id == client_id) return record.id;
    }
    return null;
}

// ===== Queries =====

pub fn clientForDisplay(m: *const model_mod.Model, display: *wlc.wl_display) ?types.ClientId {
    return m.client_by_display.get(display);
}

pub fn clientForWlClient(m: *const model_mod.Model, wl_client: *wls.wl_client) ?types.ClientId {
    return m.client_by_wl_client.get(wl_client);
}

// ===== Policy =====

pub fn disconnectPolicy(m: *const model_mod.Model, id: types.ClientId) bool {
    _ = m;
    _ = id;
    return true;
}

// ===== production code above =====

test "clientCreate registers a client and clientDestroy removes it" {
    var m = model_mod.Model.init(std.testing.allocator);
    defer m.deinit();
    const id = try clientCreate(&m, -1, -1);
    try std.testing.expect(m.clients.contains(id));
    clientDestroy(&m, id);
    try std.testing.expect(!m.clients.contains(id));
}
