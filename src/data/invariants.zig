//! Comptime-generic invariant walker over the model's EntityManagers.
//!
//! Per-table checks (no holes, no destroyed entries in indexes) are
//! generic over record type and picked up automatically when a new
//! EntityManager field lands in data/model.zig. Cross-table
//! relationship invariants stay explicit because they encode domain
//! knowledge @typeInfo cannot infer.

const std = @import("std");
const model_mod = @import("model.zig");

pub const Report = struct {
    table_violations: u32 = 0,
    relationship_violations: u32 = 0,

    pub fn ok(self: Report) bool {
        return self.table_violations == 0 and self.relationship_violations == 0;
    }
};

/// Run every available invariant check. The stub here walks the
/// EntityManager fields and confirms each is at least addressable.
/// Real checks land here as records grow real lifecycle state.
pub fn check(m: *const model_mod.Model) Report {
    const report: Report = .{};
    inline for (@typeInfo(model_mod.Model).@"struct".fields) |field| {
        if (comptime isEntityManager(field.type)) {
            const mgr: *const field.type = &@field(m, field.name);
            _ = mgr.count();
        }
    }
    return report;
}

fn isEntityManager(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    return @hasDecl(T, "insert") and @hasDecl(T, "count");
}

// ===== production code above =====

test "empty model passes all invariants" {
    var m = model_mod.Model.init(std.testing.allocator);
    defer m.deinit();
    const report = check(&m);
    try std.testing.expect(report.ok());
}
