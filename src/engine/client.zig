//! Client lifecycle: ops, queries, and policy.
//!
//! Per docs/dod.md § Operations and § Systems. Mutation and policy
//! live together per domain; the boundary lives in function naming
//! rather than in the directory tree.

const std = @import("std");
const types = @import("../data/types.zig");
const model_mod = @import("../data/model.zig");
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

pub fn clientDestroy(m: *model_mod.Model, id: types.ClientId) void {
    if (m.clients.getMutable(id)) |c| {
        c.state = .closing;
    }
    // TODO: walk owned resources, embeds, surfaces, buffers per the
    // teardown order in docs/architecture.md § Teardown Order.
    _ = m.clients.delete(id);
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
