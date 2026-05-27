//! Cross-domain engine integration tests.

const std = @import("std");
const wayplug = @import("wayplug");

test "embed attaches a child surface and clears on destroy" {
    var m = wayplug.data.model.Model.init(std.testing.allocator);
    defer m.deinit();

    const cid = try wayplug.engine.client.clientCreate(&m, -1, -1);
    const parent_rid = try m.nextResourceId();
    const child_rid = try m.nextResourceId();
    const parent_sid = try wayplug.engine.surface.surfaceCreate(&m, cid, parent_rid);
    const child_sid = try wayplug.engine.surface.surfaceCreate(&m, cid, child_rid);

    const eid = try wayplug.engine.embed.embedCreate(&m, cid, parent_sid);
    try wayplug.engine.embed.embedAttachChild(&m, eid, child_sid);
    try wayplug.engine.embed.embedResize(&m, eid, 320, 240);

    const e = m.embeds.get(eid).?;
    try std.testing.expect(e.state == .child_ready);
    try std.testing.expect(e.width == 320);
    try std.testing.expect(wayplug.engine.embed.embedForChildSurface(&m, child_sid).? == eid);

    wayplug.engine.embed.embedDestroy(&m, eid);
    try std.testing.expect(wayplug.engine.embed.embedForChildSurface(&m, child_sid) == null);
}

test "effect queue retains append order until cleared" {
    var q = wayplug.engine.effects.Queue.init(std.testing.allocator);
    defer q.deinit();

    try q.push(.{ .client_connected = @enumFromInt(1) });
    try q.push(.diagnostics_dirty);
    try q.push(.{ .embed_mapped = @enumFromInt(7) });

    const pending = q.pending();
    try std.testing.expectEqual(@as(usize, 3), pending.len);
    try std.testing.expect(pending[2] == .embed_mapped);

    q.clear();
    try std.testing.expectEqual(@as(usize, 0), q.count());
}
