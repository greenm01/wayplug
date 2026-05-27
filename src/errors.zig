//! Error set used across the engine and C ABI translation helpers.

const std = @import("std");

pub const Error = error{
    NotImplemented,
    OutOfMemory,
    InvalidArgument,
    UnknownClient,
    UnknownResource,
    UnknownSurface,
    UnknownEmbed,
    IdSpaceExhausted,
    ProtocolError,
};

/// Translate an internal error to the C-side null/zero/negative convention
/// described in docs/style-guide.md § Error Handling.
pub fn toNull(comptime T: type, err: Error) ?T {
    _ = err;
    return null;
}

pub fn toBool(err: Error) bool {
    _ = err;
    return false;
}

pub fn toInt(err: Error) c_int {
    _ = err;
    return -1;
}

test "error set is non-empty" {
    const e: Error = error.NotImplemented;
    try std.testing.expect(e == Error.NotImplemented);
}
