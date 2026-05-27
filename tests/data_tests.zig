//! Cross-module data-layer integration tests. Exercises the public
//! `data.*` surface via `@import("wayembed")`.

const std = @import("std");
const wayembed = @import("wayembed");

test "snapshot picks up records inserted across two domains" {
    var m = wayembed.data.model.Model.init(std.testing.allocator);
    defer m.deinit();

    const cid = try wayembed.engine.client.clientCreate(&m, -1, -1);
    const sid = try wayembed.engine.surface.surfaceCreate(
        &m,
        cid,
        @enumFromInt(1),
    );

    var snap = try wayembed.data.snapshot.snapshot(std.testing.allocator, &m);
    defer wayembed.data.snapshot.snapshotFree(&snap);

    try std.testing.expectEqual(@as(usize, 1), snap.counts.clients);
    try std.testing.expectEqual(@as(usize, 1), snap.counts.surfaces);
    try std.testing.expectEqual(cid, snap.clients[0].id);
    try std.testing.expectEqual(sid, snap.surfaces[0].id);

    m.clients.getMutable(cid).?.state = .closing;
    try std.testing.expect(snap.clients[0].state == .connected);
}

test "snapshot owns records after model deinit" {
    var snap: wayembed.data.snapshot.Snapshot = undefined;
    const cid = blk: {
        var m = wayembed.data.model.Model.init(std.testing.allocator);
        const id = try wayembed.engine.client.clientCreate(&m, -1, -1);
        snap = try wayembed.data.snapshot.snapshot(std.testing.allocator, &m);
        m.deinit();
        break :blk id;
    };
    defer wayembed.data.snapshot.snapshotFree(&snap);

    try std.testing.expectEqual(@as(usize, 1), snap.clients.len);
    try std.testing.expectEqual(cid, snap.clients[0].id);
}

test "invariants pass after a normal create/destroy round-trip" {
    var m = wayembed.data.model.Model.init(std.testing.allocator);
    defer m.deinit();

    const cid = try wayembed.engine.client.clientCreate(&m, -1, -1);
    wayembed.engine.client.clientDestroy(&m, cid);

    const report = wayembed.data.invariants.check(&m);
    try std.testing.expect(report.ok());
}
