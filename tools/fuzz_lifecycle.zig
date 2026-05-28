//! Standalone lifecycle fuzz runner.
//!
//! Usage:
//!   zig build fuzz-lifecycle
//!   zig build fuzz-lifecycle -- corpus/file1 corpus/file2
//!   zig build fuzz-lifecycle -- --bytes=minimized-corpus-bytes

const std = @import("std");
const harness = @import("fuzz_harness");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.skip();

    var saw_arg = false;
    while (args.next()) |arg| {
        saw_arg = true;
        if (std.mem.startsWith(u8, arg, "--bytes=")) {
            try harness.runLifecycleBytes(allocator, arg["--bytes=".len..], "argv");
            continue;
        }

        const input = try std.Io.Dir.cwd().readFileAlloc(init.io, arg, allocator, .limited(1024 * 1024));
        defer allocator.free(input);
        try harness.runLifecycleBytes(allocator, input, arg);
    }

    if (!saw_arg) {
        const seeds = [_]u64{
            0x1199_2026_1000_0001,
            0x1199_2026_1000_0002,
            0x1199_2026_1000_0003,
            0x1199_2026_1000_0004,
            0x1199_2026_1000_0005,
            0x1199_2026_1000_0006,
            0x1199_2026_1000_0007,
            0x1199_2026_1000_0008,
            0x1199_2026_1000_0009,
            0x1199_2026_1000_000a,
            0x1199_2026_1000_000b,
            0x1199_2026_1000_000c,
            0x1199_2026_1000_000d,
            0x1199_2026_1000_000e,
            0x1199_2026_1000_000f,
            0x1199_2026_1000_0010,
        };
        for (seeds) |seed| {
            try harness.runLifecycleSeedWithAllocator(allocator, seed, 1024);
        }
    }
}
