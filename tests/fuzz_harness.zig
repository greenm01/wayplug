//! Reusable deterministic fuzz harness for lifecycle and delegate cleanup.

const std = @import("std");
const wayembed = @import("wayembed");

const Engine = wayembed.engine.Engine;
const types = wayembed.data.types;

const Rng = struct {
    state: u64,

    fn init(seed: u64) Rng {
        return .{ .state = seed };
    }

    fn next(self: *Rng) u64 {
        self.state = self.state *% 6364136223846793005 +% 1442695040888963407;
        return self.state;
    }

    fn below(self: *Rng, limit: usize) usize {
        std.debug.assert(limit > 0);
        return @intCast(self.next() % limit);
    }
};

const Trace = struct {
    source: []const u8,
    seed: u64 = 0,
    step: usize,
    op: usize,
};

pub fn runLifecycleSeed(seed: u64, steps: usize) !void {
    try runLifecycleSeedWithAllocator(std.testing.allocator, seed, steps);
}

pub fn runLifecycleSeedWithAllocator(allocator: std.mem.Allocator, seed: u64, steps: usize) !void {
    var engine = Engine.init(allocator);
    defer engine.deinit();

    var rng = Rng.init(seed);
    for (0..steps) |step| {
        const op = rng.below(12);
        const trace: Trace = .{ .source = "seed", .seed = seed, .step = step, .op = op };
        try applyOp(&engine, &rng, op);
        try expectClean(&engine, trace);
    }
}

pub fn runLifecycleBytes(allocator: std.mem.Allocator, bytes: []const u8, label: []const u8) !void {
    var engine = Engine.init(allocator);
    defer engine.deinit();

    var cursor = ByteCursor{ .bytes = bytes };
    var step: usize = 0;
    while (cursor.next()) |byte| : (step += 1) {
        const op = byte % 12;
        var rng = Rng.init(cursor.seedForStep(step, byte));
        const trace: Trace = .{ .source = label, .step = step, .op = op };
        try applyOp(&engine, &rng, op);
        try expectClean(&engine, trace);
    }
}

fn applyOp(engine: *Engine, rng: *Rng, op: usize) !void {
    switch (op) {
        0 => _ = try engine.clientCreate(-1, -1),
        1 => try createSurface(engine, rng),
        2 => try createBuffer(engine, rng),
        3 => try createOutput(engine, rng),
        4 => try createEmbedGraph(engine, rng),
        5 => try destroyRandomClient(engine, rng),
        6 => try destroyRandomEmbed(engine, rng),
        7 => try destroyRandomBuffer(engine, rng),
        8 => try destroyRandomOutput(engine, rng),
        9 => try destroyRandomFreeSurface(engine, rng),
        10 => try destroyRandomFreeResource(engine, rng),
        11 => try queueProtocolError(engine, rng),
        else => unreachable,
    }
}

fn expectClean(engine: *const Engine, trace: Trace) !void {
    const report = wayembed.data.invariants.check(&engine.model);
    if (!report.ok()) {
        if (trace.seed != 0) {
            std.debug.print(
                "lifecycle fuzz failed source={s} seed=0x{x} step={} op={} table={} relationship={}\n",
                .{ trace.source, trace.seed, trace.step, trace.op, report.table_violations, report.relationship_violations },
            );
        } else {
            std.debug.print(
                "lifecycle fuzz failed source={s} step={} op={} table={} relationship={}\n",
                .{ trace.source, trace.step, trace.op, report.table_violations, report.relationship_violations },
            );
        }
        return error.LifecycleFuzzInvariantViolation;
    }
}

fn createSurface(engine: *Engine, rng: *Rng) !void {
    const client_id = pickClient(engine, rng) orelse return;
    const resource_id = try engine.resourceCreate(client_id, .surface, null, null);
    _ = try engine.surfaceCreate(client_id, resource_id);
}

fn createBuffer(engine: *Engine, rng: *Rng) !void {
    const client_id = pickClient(engine, rng) orelse return;
    const resource_id = try engine.resourceCreate(client_id, .buffer, null, null);
    _ = try wayembed.engine.buffer.bufferCreate(&engine.model, client_id, resource_id);
}

fn createOutput(engine: *Engine, rng: *Rng) !void {
    const client_id = pickClient(engine, rng) orelse return;
    const resource_id = try engine.resourceCreate(client_id, .output, null, null);
    _ = try engine.outputCreate(resource_id, @intCast(rng.next() & 0xffff_ffff));
}

fn createEmbedGraph(engine: *Engine, rng: *Rng) !void {
    const client_id = pickClient(engine, rng) orelse return;
    const parent_resource_id = try engine.resourceCreate(client_id, .surface, null, null);
    const child_resource_id = try engine.resourceCreate(client_id, .surface, null, null);
    const subsurface_resource_id = try engine.resourceCreate(client_id, .subsurface, null, null);
    const parent_surface_id = try engine.surfaceCreate(client_id, parent_resource_id);
    const child_surface_id = try engine.surfaceCreate(client_id, child_resource_id);
    const embed_id = try engine.embedCreate(client_id, parent_surface_id);
    try engine.embedAttachChild(embed_id, child_surface_id);
    try engine.embedSetSubsurfaceResource(embed_id, subsurface_resource_id);
    if (rng.below(2) == 0) try engine.embedMap(embed_id);
}

fn destroyRandomClient(engine: *Engine, rng: *Rng) !void {
    const id = pickClient(engine, rng) orelse return;
    try engine.clientDestroy(id);
    try engine.clientDestroy(id);
}

fn destroyRandomEmbed(engine: *Engine, rng: *Rng) !void {
    const id = pickEmbed(engine, rng) orelse return;
    try engine.embedDestroy(id);
    try engine.embedDestroy(id);
}

fn destroyRandomBuffer(engine: *Engine, rng: *Rng) !void {
    const id = pickBuffer(engine, rng) orelse return;
    wayembed.engine.buffer.bufferDestroy(&engine.model, id);
    wayembed.engine.buffer.bufferDestroy(&engine.model, id);
}

fn destroyRandomOutput(engine: *Engine, rng: *Rng) !void {
    const id = pickOutput(engine, rng) orelse return;
    engine.outputDestroy(id);
    engine.outputDestroy(id);
}

fn destroyRandomFreeSurface(engine: *Engine, rng: *Rng) !void {
    const id = pickFreeSurface(engine, rng) orelse return;
    wayembed.engine.surface.surfaceDestroy(&engine.model, id);
    wayembed.engine.surface.surfaceDestroy(&engine.model, id);
}

fn destroyRandomFreeResource(engine: *Engine, rng: *Rng) !void {
    const id = pickFreeResource(engine, rng) orelse return;
    engine.resourceDestroy(id);
    engine.resourceDestroy(id);
}

fn queueProtocolError(engine: *Engine, rng: *Rng) !void {
    const id = pickClient(engine, rng) orelse return;
    try engine.protocolError(id, @intCast(rng.next() & 0xffff_ffff));
}

fn pickClient(engine: *const Engine, rng: *Rng) ?types.ClientId {
    if (engine.model.clients.count() == 0) return null;
    return engine.model.clients.items()[rng.below(engine.model.clients.count())].id;
}

fn pickEmbed(engine: *const Engine, rng: *Rng) ?types.EmbedId {
    if (engine.model.embeds.count() == 0) return null;
    return engine.model.embeds.items()[rng.below(engine.model.embeds.count())].id;
}

fn pickBuffer(engine: *const Engine, rng: *Rng) ?types.BufferId {
    if (engine.model.buffers.count() == 0) return null;
    return engine.model.buffers.items()[rng.below(engine.model.buffers.count())].id;
}

fn pickOutput(engine: *const Engine, rng: *Rng) ?types.OutputId {
    if (engine.model.outputs.count() == 0) return null;
    return engine.model.outputs.items()[rng.below(engine.model.outputs.count())].id;
}

fn pickFreeSurface(engine: *const Engine, rng: *Rng) ?types.SurfaceId {
    const count = countFreeSurfaces(engine);
    if (count == 0) return null;
    var target = rng.below(count);
    for (engine.model.surfaces.items()) |surface| {
        if (surfaceUsedByEmbed(engine, surface.id)) continue;
        if (target == 0) return surface.id;
        target -= 1;
    }
    return null;
}

fn pickFreeResource(engine: *const Engine, rng: *Rng) ?types.ResourceId {
    const count = countFreeResources(engine);
    if (count == 0) return null;
    var target = rng.below(count);
    for (engine.model.resources.items()) |resource| {
        if (resourceHasDependents(engine, resource.id)) continue;
        if (target == 0) return resource.id;
        target -= 1;
    }
    return null;
}

fn countFreeSurfaces(engine: *const Engine) usize {
    var count: usize = 0;
    for (engine.model.surfaces.items()) |surface| {
        if (!surfaceUsedByEmbed(engine, surface.id)) count += 1;
    }
    return count;
}

fn countFreeResources(engine: *const Engine) usize {
    var count: usize = 0;
    for (engine.model.resources.items()) |resource| {
        if (!resourceHasDependents(engine, resource.id)) count += 1;
    }
    return count;
}

fn surfaceUsedByEmbed(engine: *const Engine, id: types.SurfaceId) bool {
    return engine.model.embed_by_parent_surface.get(id) != null or
        engine.model.embed_by_child_surface.get(id) != null;
}

fn resourceHasDependents(engine: *const Engine, id: types.ResourceId) bool {
    if (engine.model.surface_by_resource.get(id) != null) return true;
    if (engine.model.buffer_by_resource.get(id) != null) return true;
    if (wayembed.engine.output.outputForResource(&engine.model, id) != null) return true;
    for (engine.model.embeds.items()) |embed| {
        if (embed.subsurface_resource_id == id) return true;
    }
    return false;
}

const ByteCursor = struct {
    bytes: []const u8,
    index: usize = 0,

    fn next(self: *ByteCursor) ?u8 {
        if (self.index >= self.bytes.len) return null;
        const byte = self.bytes[self.index];
        self.index += 1;
        return byte;
    }

    fn seedForStep(self: ByteCursor, step: usize, byte: u8) u64 {
        var seed: u64 = 0xcbf29ce484222325;
        seed ^= @as(u64, @intCast(step));
        seed *%= 0x100000001b3;
        seed ^= byte;
        seed *%= 0x100000001b3;
        if (self.index < self.bytes.len) seed ^= self.bytes[self.index];
        return seed;
    }
};
