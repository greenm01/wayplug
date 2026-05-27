//! Engine facade. The protocol layer and c_api.zig reach into the
//! engine only through this module. Domain-specific ops, queries, and
//! policy live in sibling files.

const std = @import("std");
const types = @import("../data/types.zig");
const model_mod = @import("../data/model.zig");

pub const client = @import("client.zig");
pub const resource = @import("resource.zig");
pub const surface = @import("surface.zig");
pub const buffer = @import("buffer.zig");
pub const embed = @import("embed.zig");
pub const output = @import("output.zig");
pub const effects = @import("effects.zig");

pub const Engine = struct {
    model: model_mod.Model,
    effects: effects.Queue,
    state: types.ServerState = .stopped,

    pub fn init(allocator: std.mem.Allocator) Engine {
        return .{
            .model = model_mod.Model.init(allocator),
            .effects = effects.Queue.init(allocator),
        };
    }

    pub fn deinit(self: *Engine) void {
        self.effects.deinit();
        self.model.deinit();
    }
};

// ===== production code above =====

test "Engine init/deinit round-trips" {
    var e = Engine.init(std.testing.allocator);
    defer e.deinit();
    try std.testing.expect(e.state == .stopped);
}
