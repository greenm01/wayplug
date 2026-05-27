# AGENTS.md - guide for AI coding agents

This file documents project conventions, build mechanics, and architecture
rules for agents working on `wayembed`. Humans should read `README.md` first;
this file adds the operational details an agent needs to act safely.

## Working Rules

1. Think before coding. State assumptions, surface tradeoffs, and ask only when
   intent is genuinely ambiguous.
2. Keep changes simple. Do not add speculative features, abstractions, or
   configurability.
3. Make surgical edits. Touch only files needed for the request and clean up
   only the mess your change creates.
4. Define verification. Turn every bugfix or feature into concrete checks and
   run them before finishing when feasible.
5. Format Zig files with `zig fmt`. Run it on touched `.zig` files before
   verification.
6. Run `zig build test` after code changes unless the change is docs-only or
   the user explicitly asks not to run tests.
7. Do not run Zig builds or tests in parallel. They share `.zig-cache` and
   `zig-out`; concurrent invocations can produce confusing or stale results.
8. Keep the public ABI stable. Changes to `include/wayembed.h` must preserve C
   ABI compatibility unless the ABI version is intentionally changed.
9. Keep source files small and focused. If a file grows too broad, split it by
   domain according to `docs/architecture.md`.
10. Keep data separate from logic. Follow `docs/dod.md` when touching the
    `data/` model, `engine/` operations, queries, or policy code.
11. Follow `docs/style-guide.md` for Zig style, C ABI rules, naming, ownership,
    error handling, and module boundaries.
12. Re-read `docs/architecture.md`, `docs/dod.md`, and
    `docs/style-guide.md` after context compaction or when resuming a long
    task that touches architecture-sensitive code.

## Architecture Direction

The runtime model is the source of truth. Production code should not rebuild
a parallel Wayland-shaped object graph or bypass the engine facade.

When changing `data/`, `engine/`, or `protocol/` code:

1. Prefer indexed queries and iterators over allocation-returning helpers in hot
   dispatch paths.
2. Keep mutation centralized in `src/engine/`. Protocol delegates and
   `c_api.zig` should use `src/engine/engine.zig` instead of reaching into
   `src/data/` tables or indexes directly.
3. Keep protocol code as a thin adapter: translate Wayland callbacks into
   direct forwarding for simple requests, or into operations for lifecycle
   changes.
4. Use direct forwarding for hot protocol paths such as `wl_surface.attach`,
   `damage`, `commit`, pointer motion, keyboard events, and buffer-release
   forwarding.
5. Use operations for lifecycle-sensitive events such as client connect/close,
   resource create/destroy, surface role assignment, subsurface creation, embed
   resize/destroy, protocol errors, and parent-surface withdrawal.
6. Keep host policy above protocol mechanics. Protocol delegates validate
   and translate; the engine decides policy.

## C ABI Rules

The public boundary is C.

1. Public structs must be versioned or size-checked.
2. Public handles must be opaque.
3. Public functions must use C-callable types only.
4. Do not expose Zig structs, slices, allocators, error unions, optionals, or
   comptime concepts in `include/wayembed.h`.
5. Returned ownership must be explicit in the header.
6. If `include/wayembed.h` changes, update docs and C ABI smoke coverage.

## Verification

Use these commands from the repository root:

```sh
zig fmt src build.zig
zig build test
```

For docs-only changes, no build is required unless the docs include generated
examples or code that should be compiled.

For ABI changes, run:

```sh
zig build test
```

and check that `tests/c_abi_smoke.c` still exercises the changed surface.

## Debugging Evidence

For protocol, lifecycle, or compositor-specific bugs, prefer evidence that can
be compared across runs:

- server/client state snapshots
- resource and embed ids
- protocol error records
- client connect/disconnect logs
- resource create/destroy logs
- compositor name and protocol globals
- exact Wayland protocol path involved

Do not delete generated diagnostics as cleanup unless the task specifically
requires it. Diagnostics are often the best evidence for teardown and lifecycle
bugs.
