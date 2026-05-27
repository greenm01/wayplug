//! Surface lifecycle: ops, role assignment, and queries.

const std = @import("std");
const types = @import("../data/types.zig");
const model_mod = @import("../data/model.zig");

pub fn surfaceCreate(
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

pub fn surfaceDestroy(m: *model_mod.Model, id: types.SurfaceId) void {
    if (m.surfaces.get(id)) |s| {
        _ = m.surface_by_resource.swapRemove(s.resource_id);
    }
    _ = m.surfaces.delete(id);
}

pub fn assignRole(m: *model_mod.Model, id: types.SurfaceId, role: types.SurfaceRole) !void {
    const s = m.surfaces.getMutable(id) orelse return error.UnknownSurface;
    if (s.role != .none and s.role != role) return error.RoleAlreadyAssigned;
    s.role = role;
}

pub fn surfaceRole(m: *const model_mod.Model, id: types.SurfaceId) ?types.SurfaceRole {
    const s = m.surfaces.get(id) orelse return null;
    return s.role;
}

pub fn surfaceForResource(m: *const model_mod.Model, rid: types.ResourceId) ?types.SurfaceId {
    return m.surface_by_resource.get(rid);
}

// ===== production code above =====

test "surface create, role assign, destroy" {
    var m = model_mod.Model.init(std.testing.allocator);
    defer m.deinit();
    const cid = try m.nextClientId();
    const rid = try m.nextResourceId();
    const sid = try surfaceCreate(&m, cid, rid);
    try assignRole(&m, sid, .subsurface);
    try std.testing.expect(m.surfaces.get(sid).?.role == .subsurface);
    surfaceDestroy(&m, sid);
    try std.testing.expect(!m.surfaces.contains(sid));
}

test "surface role assignment rejects conflicting roles" {
    var m = model_mod.Model.init(std.testing.allocator);
    defer m.deinit();
    const cid = try m.nextClientId();
    const rid = try m.nextResourceId();
    const sid = try surfaceCreate(&m, cid, rid);

    try assignRole(&m, sid, .toplevel);
    try std.testing.expectError(error.RoleAlreadyAssigned, assignRole(&m, sid, .popup));
    try std.testing.expect(m.surfaces.get(sid).?.role == .toplevel);
}

test "surface role query returns current role" {
    var m = model_mod.Model.init(std.testing.allocator);
    defer m.deinit();
    const cid = try m.nextClientId();
    const rid = try m.nextResourceId();
    const sid = try surfaceCreate(&m, cid, rid);

    try std.testing.expect(surfaceRole(&m, sid).? == .none);
    try assignRole(&m, sid, .popup);
    try std.testing.expect(surfaceRole(&m, sid).? == .popup);
}
