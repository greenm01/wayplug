//! Cross-module data-layer integration tests. Exercises the public
//! `data.*` surface via `@import("wayplug")`.

const std = @import("std");
const wayplug = @import("wayplug");

test "snapshot picks up records inserted across two domains" {
    var m = wayplug.data.model.Model.init(std.testing.allocator);
    defer m.deinit();

    const cid = try wayplug.engine.client.clientCreate(&m, -1, -1);
    const sid = try wayplug.engine.surface.surfaceCreate(
        &m,
        cid,
        @enumFromInt(1),
    );

    var snap = try wayplug.data.snapshot.snapshot(std.testing.allocator, &m);
    defer wayplug.data.snapshot.snapshotFree(&snap);

    try std.testing.expectEqual(@as(usize, 1), snap.counts.clients);
    try std.testing.expectEqual(@as(usize, 1), snap.counts.surfaces);
    try std.testing.expectEqual(cid, snap.clients[0].id);
    try std.testing.expectEqual(sid, snap.surfaces[0].id);

    m.clients.getMutable(cid).?.state = .closing;
    try std.testing.expect(snap.clients[0].state == .connected);
}

test "snapshot owns records after model deinit" {
    var snap: wayplug.data.snapshot.Snapshot = undefined;
    const cid = blk: {
        var m = wayplug.data.model.Model.init(std.testing.allocator);
        const id = try wayplug.engine.client.clientCreate(&m, -1, -1);
        snap = try wayplug.data.snapshot.snapshot(std.testing.allocator, &m);
        m.deinit();
        break :blk id;
    };
    defer wayplug.data.snapshot.snapshotFree(&snap);

    try std.testing.expectEqual(@as(usize, 1), snap.clients.len);
    try std.testing.expectEqual(cid, snap.clients[0].id);
}

test "invariants pass after a normal create/destroy round-trip" {
    var m = wayplug.data.model.Model.init(std.testing.allocator);
    defer m.deinit();

    const cid = try wayplug.engine.client.clientCreate(&m, -1, -1);
    wayplug.engine.client.clientDestroy(&m, cid);

    const report = wayplug.data.invariants.check(&m);
    try std.testing.expect(report.ok());
}
