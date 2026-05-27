//! Comptime-generic invariant walker over the model's EntityManagers.
//!
//! Per-table checks (no holes, no destroyed entries in indexes) are
//! generic over record type and picked up automatically when a new
//! EntityManager field lands in data/model.zig. Cross-table
//! relationship invariants stay explicit because they encode domain
//! knowledge @typeInfo cannot infer.

const std = @import("std");
const model_mod = @import("model.zig");
const types = @import("types.zig");

pub const Report = struct {
    table_violations: u32 = 0,
    relationship_violations: u32 = 0,

    pub fn ok(self: Report) bool {
        return self.table_violations == 0 and self.relationship_violations == 0;
    }
};

/// Run every available invariant check.
pub fn check(m: *const model_mod.Model) Report {
    var report: Report = .{};
    inline for (@typeInfo(model_mod.Model).@"struct".fields) |field| {
        if (comptime isEntityManager(field.type)) {
            const mgr: *const field.type = &@field(m, field.name);
            report.table_violations += checkTable(field.type, mgr);
        }
    }
    report.relationship_violations += checkClientIndexes(m);
    report.relationship_violations += checkResourceIndexes(m);
    report.relationship_violations += checkSurfaceIndexes(m);
    report.relationship_violations += checkBufferIndexes(m);
    report.relationship_violations += checkEmbedIndexes(m);
    report.relationship_violations += checkRelationships(m);
    return report;
}

fn isEntityManager(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    return @hasDecl(T, "insert") and @hasDecl(T, "count") and @hasDecl(T, "Key");
}

fn checkTable(comptime Manager: type, mgr: *const Manager) u32 {
    var violations: u32 = 0;
    if (mgr.records.items.len != mgr.index_by_id.count()) violations += 1;

    for (mgr.records.items, 0..) |record, index| {
        const mapped = mgr.index_by_id.get(record.id) orelse {
            violations += 1;
            continue;
        };
        if (mapped != index) violations += 1;
    }

    for (mgr.index_by_id.keys(), mgr.index_by_id.values()) |key, index| {
        if (index >= mgr.records.items.len) {
            violations += 1;
            continue;
        }
        if (mgr.records.items[index].id != key) violations += 1;
    }
    return violations;
}

fn checkClientIndexes(m: *const model_mod.Model) u32 {
    var violations: u32 = 0;

    for (m.client_by_wl_client.keys(), m.client_by_wl_client.values()) |wl_client, client_id| {
        const client = m.clients.get(client_id) orelse {
            violations += 1;
            continue;
        };
        if (client.wl_client != wl_client) violations += 1;
    }

    for (m.client_by_display.keys(), m.client_by_display.values()) |display, client_id| {
        const client = m.clients.get(client_id) orelse {
            violations += 1;
            continue;
        };
        if (client.wl_display != display) violations += 1;
    }

    for (m.clients.items()) |client| {
        if (client.wl_client) |wl_client| {
            if (m.client_by_wl_client.get(wl_client) != client.id) violations += 1;
        }
        if (client.wl_display) |display| {
            if (m.client_by_display.get(display) != client.id) violations += 1;
        }
    }
    return violations;
}

fn checkResourceIndexes(m: *const model_mod.Model) u32 {
    var violations: u32 = 0;

    for (m.resource_by_wl_resource.keys(), m.resource_by_wl_resource.values()) |wl_resource, resource_id| {
        const resource = m.resources.get(resource_id) orelse {
            violations += 1;
            continue;
        };
        if (resource.wl_resource != wl_resource) violations += 1;
        if (resource.state != .alive) violations += 1;
    }

    for (m.resource_by_upstream_proxy.keys(), m.resource_by_upstream_proxy.values()) |proxy, resource_id| {
        const resource = m.resources.get(resource_id) orelse {
            violations += 1;
            continue;
        };
        if (resource.upstream_proxy != proxy) violations += 1;
        if (resource.state != .alive) violations += 1;
    }

    for (m.resources.items()) |resource| {
        if (resource.wl_resource) |wl_resource| {
            if (m.resource_by_wl_resource.get(wl_resource) != resource.id) violations += 1;
        }
        if (resource.upstream_proxy) |proxy| {
            if (m.resource_by_upstream_proxy.get(proxy) != resource.id) violations += 1;
        }
    }
    return violations;
}

fn checkSurfaceIndexes(m: *const model_mod.Model) u32 {
    var violations: u32 = 0;
    for (m.surface_by_resource.keys(), m.surface_by_resource.values()) |resource_id, surface_id| {
        const surface = m.surfaces.get(surface_id) orelse {
            violations += 1;
            continue;
        };
        if (surface.resource_id != resource_id) violations += 1;
        const resource = m.resources.get(resource_id) orelse {
            violations += 1;
            continue;
        };
        if (resource.state != .alive) violations += 1;
    }
    for (m.surfaces.items()) |surface| {
        if (m.surface_by_resource.get(surface.resource_id) != surface.id) violations += 1;
    }
    return violations;
}

fn checkBufferIndexes(m: *const model_mod.Model) u32 {
    var violations: u32 = 0;
    for (m.buffer_by_resource.keys(), m.buffer_by_resource.values()) |resource_id, buffer_id| {
        const buffer = m.buffers.get(buffer_id) orelse {
            violations += 1;
            continue;
        };
        if (buffer.resource_id != resource_id) violations += 1;
        const resource = m.resources.get(resource_id) orelse {
            violations += 1;
            continue;
        };
        if (resource.state != .alive) violations += 1;
    }
    for (m.buffers.items()) |buffer| {
        if (m.buffer_by_resource.get(buffer.resource_id) != buffer.id) violations += 1;
    }
    return violations;
}

fn checkEmbedIndexes(m: *const model_mod.Model) u32 {
    var violations: u32 = 0;
    for (m.embed_by_parent_surface.keys(), m.embed_by_parent_surface.values()) |surface_id, embed_id| {
        const embed = m.embeds.get(embed_id) orelse {
            violations += 1;
            continue;
        };
        if (embed.host_parent_surface_id != surface_id) violations += 1;
    }
    for (m.embed_by_child_surface.keys(), m.embed_by_child_surface.values()) |surface_id, embed_id| {
        const embed = m.embeds.get(embed_id) orelse {
            violations += 1;
            continue;
        };
        if (embed.plugin_child_surface_id != surface_id) violations += 1;
    }
    for (m.embeds.items()) |embed| {
        if (m.embed_by_parent_surface.get(embed.host_parent_surface_id) != embed.id) violations += 1;
        if (embed.plugin_child_surface_id != .null_id) {
            if (m.embed_by_child_surface.get(embed.plugin_child_surface_id) != embed.id) violations += 1;
        }
    }
    return violations;
}

fn checkRelationships(m: *const model_mod.Model) u32 {
    var violations: u32 = 0;

    for (m.resources.items()) |resource| {
        if (!m.clients.contains(resource.client_id)) violations += 1;
    }

    for (m.surfaces.items()) |surface| {
        if (!m.clients.contains(surface.client_id)) violations += 1;
        const resource = m.resources.get(surface.resource_id) orelse {
            violations += 1;
            continue;
        };
        if (resource.kind != .surface) violations += 1;
        if (resource.client_id != surface.client_id) violations += 1;
    }

    for (m.buffers.items()) |buffer| {
        if (!m.clients.contains(buffer.client_id)) violations += 1;
        const resource = m.resources.get(buffer.resource_id) orelse {
            violations += 1;
            continue;
        };
        if (resource.kind != .buffer) violations += 1;
        if (resource.client_id != buffer.client_id) violations += 1;
    }

    for (m.embeds.items()) |embed| {
        if (!m.clients.contains(embed.client_id)) violations += 1;
        if (!m.surfaces.contains(embed.host_parent_surface_id)) violations += 1;
        if (embed.plugin_child_surface_id != .null_id and !m.surfaces.contains(embed.plugin_child_surface_id)) {
            violations += 1;
        }
        if (embed.subsurface_resource_id != .null_id) {
            const resource = m.resources.get(embed.subsurface_resource_id) orelse {
                violations += 1;
                continue;
            };
            if (resource.kind != .subsurface) violations += 1;
            if (resource.client_id != embed.client_id) violations += 1;
        }
    }

    for (m.outputs.items()) |output| {
        const resource = m.resources.get(output.resource_id) orelse {
            violations += 1;
            continue;
        };
        if (resource.kind != .output) violations += 1;
    }
    return violations;
}

// ===== production code above =====

test "empty model passes all invariants" {
    var m = model_mod.Model.init(std.testing.allocator);
    defer m.deinit();
    const report = check(&m);
    try std.testing.expect(report.ok());
}

test "valid cross-table graph passes all invariants" {
    var m = model_mod.Model.init(std.testing.allocator);
    defer m.deinit();
    _ = try populateValidGraph(&m);

    const report = check(&m);
    try std.testing.expect(report.ok());
}

test "corrupt dense sparse mapping reports table violation" {
    var m = model_mod.Model.init(std.testing.allocator);
    defer m.deinit();

    const cid = try insertClient(&m);
    m.clients.index_by_id.getPtr(cid).?.* = 99;

    const report = check(&m);
    try std.testing.expect(report.table_violations > 0);
}

test "missing model relationships report relationship violations" {
    var m = model_mod.Model.init(std.testing.allocator);
    defer m.deinit();

    const rid = try m.nextResourceId();
    try m.resources.insert(m.allocator, rid, .{
        .id = rid,
        .client_id = @enumFromInt(777),
        .kind = .surface,
        .state = .alive,
        .wl_resource = null,
        .upstream_proxy = null,
        .generation = 1,
    });

    const report = check(&m);
    try std.testing.expect(report.relationship_violations > 0);
}

test "stale relationship indexes report relationship violations" {
    var m = model_mod.Model.init(std.testing.allocator);
    defer m.deinit();
    const ids = try populateValidGraph(&m);

    try m.surface_by_resource.put(m.allocator, @enumFromInt(999), ids.parent_surface_id);

    const report = check(&m);
    try std.testing.expect(report.relationship_violations > 0);
}

test "dead resource in relationship index reports relationship violation" {
    var m = model_mod.Model.init(std.testing.allocator);
    defer m.deinit();

    const cid = try insertClient(&m);
    const rid = try m.nextResourceId();
    try m.resources.insert(m.allocator, rid, .{
        .id = rid,
        .client_id = cid,
        .kind = .surface,
        .state = .dead,
        .wl_resource = null,
        .upstream_proxy = null,
        .generation = 1,
    });
    const sid = try m.nextSurfaceId();
    try m.surfaces.insert(m.allocator, sid, .{
        .id = sid,
        .client_id = cid,
        .resource_id = rid,
        .role = .none,
    });
    try m.surface_by_resource.put(m.allocator, rid, sid);

    const report = check(&m);
    try std.testing.expect(report.relationship_violations > 0);
}

const ValidIds = struct {
    parent_surface_id: types.SurfaceId,
};

fn populateValidGraph(m: *model_mod.Model) !ValidIds {
    const cid = try insertClient(m);

    const parent_resource_id = try insertResource(m, cid, .surface);
    const child_resource_id = try insertResource(m, cid, .surface);
    const buffer_resource_id = try insertResource(m, cid, .buffer);
    const subsurface_resource_id = try insertResource(m, cid, .subsurface);
    const output_resource_id = try insertResource(m, cid, .output);

    const parent_surface_id = try insertSurface(m, cid, parent_resource_id);
    const child_surface_id = try insertSurface(m, cid, child_resource_id);
    _ = try insertBuffer(m, cid, buffer_resource_id);
    _ = try insertOutput(m, output_resource_id);
    _ = try insertEmbed(m, cid, parent_surface_id, child_surface_id, subsurface_resource_id);

    return .{ .parent_surface_id = parent_surface_id };
}

fn insertClient(m: *model_mod.Model) !types.ClientId {
    const id = try m.nextClientId();
    try m.clients.insert(m.allocator, id, .{
        .id = id,
        .state = .connected,
        .server_fd = -1,
        .client_fd = -1,
        .wl_client = null,
        .wl_display = null,
    });
    return id;
}

fn insertResource(
    m: *model_mod.Model,
    client_id: types.ClientId,
    kind: types.ResourceKind,
) !types.ResourceId {
    const id = try m.nextResourceId();
    try m.resources.insert(m.allocator, id, .{
        .id = id,
        .client_id = client_id,
        .kind = kind,
        .state = .alive,
        .wl_resource = null,
        .upstream_proxy = null,
        .generation = 1,
    });
    return id;
}

fn insertSurface(
    m: *model_mod.Model,
    client_id: types.ClientId,
    resource_id: types.ResourceId,
) !types.SurfaceId {
    const id = try m.nextSurfaceId();
    try m.surfaces.insert(m.allocator, id, .{
        .id = id,
        .client_id = client_id,
        .resource_id = resource_id,
        .role = .none,
    });
    try m.surface_by_resource.put(m.allocator, resource_id, id);
    return id;
}

fn insertBuffer(
    m: *model_mod.Model,
    client_id: types.ClientId,
    resource_id: types.ResourceId,
) !types.BufferId {
    const id = try m.nextBufferId();
    try m.buffers.insert(m.allocator, id, .{
        .id = id,
        .client_id = client_id,
        .resource_id = resource_id,
    });
    try m.buffer_by_resource.put(m.allocator, resource_id, id);
    return id;
}

fn insertOutput(m: *model_mod.Model, resource_id: types.ResourceId) !types.OutputId {
    const id = try m.nextOutputId();
    try m.outputs.insert(m.allocator, id, .{
        .id = id,
        .resource_id = resource_id,
        .name = 1,
    });
    return id;
}

fn insertEmbed(
    m: *model_mod.Model,
    client_id: types.ClientId,
    parent_surface_id: types.SurfaceId,
    child_surface_id: types.SurfaceId,
    subsurface_resource_id: types.ResourceId,
) !types.EmbedId {
    const id = try m.nextEmbedId();
    try m.embeds.insert(m.allocator, id, .{
        .id = id,
        .client_id = client_id,
        .state = .child_ready,
        .host_parent_surface_id = parent_surface_id,
        .plugin_child_surface_id = child_surface_id,
        .subsurface_resource_id = subsurface_resource_id,
        .x = 0,
        .y = 0,
        .width = 640,
        .height = 480,
    });
    try m.embed_by_parent_surface.put(m.allocator, parent_surface_id, id);
    try m.embed_by_child_surface.put(m.allocator, child_surface_id, id);
    return id;
}
