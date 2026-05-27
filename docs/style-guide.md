# Style Guide

This guide defines the code style and architecture discipline for `wayplug`.
The formatter handles whitespace; this guide handles judgment.

## Formatter

Use `zig fmt`.

```sh
zig fmt src build.zig
```

Do not hand-align code against the formatter. If a construct becomes hard to
read after formatting, simplify the construct.

## Naming

Use names that make ownership and layer boundaries obvious.

Zig code:

- Types: `PascalCase`
- Functions: `camelCase`
- Variables and fields: `snake_case`
- Files and modules: `snake_case.zig`
- Enum tags: `snake_case`
- Internal constants: `PascalCase` for type-like constants, `snake_case` for
  ordinary values

C ABI:

- Public functions: `wayplug_snake_case`
- Public structs: `wayplug_snake_case`
- Public macros: `WAYPLUG_UPPER_SNAKE_CASE`
- Public typedefs: `wayplug_snake_case`

Examples:

```zig
pub const ResourceId = enum(u32) { null_id = 0, _ };

pub const Resource = struct {
    id: ResourceId,
    client_id: ClientId,
    upstream_proxy: ?*wl_proxy,
};

pub fn resourceForWlResource(model: *const Model, resource: *wl_resource) ?ResourceId {
    return model.resource_by_wl_resource.get(resource);
}
```

```c
#define WAYPLUG_ABI_VERSION 1u

typedef struct wayplug_server wayplug_server;

uint32_t wayplug_abi_version(void);
```

## Data And Logic

Keep data passive.

`src/data/types.zig` defines records, ids, enums, and flags. It should not
own protocol forwarding, cleanup policy, or cross-table mutation.

Good:

```zig
pub const Embed = struct {
    id: EmbedId,
    client_id: ClientId,
    state: EmbedState,
    host_parent_surface_id: SurfaceId,
    plugin_child_surface_id: SurfaceId,
};
```

Avoid:

```zig
pub const Embed = struct {
    // ...

    pub fn destroy(self: *Embed, server: *Server) void {
        // Cross-table cleanup does not belong in a data record.
    }
};
```

Cross-table mutation and policy both belong in `src/engine/<domain>.zig`,
together with that domain's queries. Protocol translation belongs in
`src/protocol/`.

## Generic Walkers

Comptime `@typeInfo()` is the right tool for code that operates *across*
record types: snapshot serialization, per-table invariant checks,
diagnostic dumps. `src/data/snapshot.zig` and `src/data/invariants.zig`
use it so adding a record to `src/data/model.zig` extends both for free.

Generic walkers stay out of hot paths. Protocol forwarding uses direct
field access and named lookups; the `@typeInfo()` cost is paid at comptime
for diagnostics and tests, never per-dispatch.

## Single Lookup

Avoid looking up the same entity twice.

Bad:

```zig
if (model.resources.contains(id)) {
    const resource = model.resources.get(id).?;
    _ = resource;
}
```

Good:

```zig
if (model.resources.get(id)) |resource| {
    _ = resource;
}
```

For mutation, prefer a single mutable lookup:

```zig
if (model.resources.getPtr(id)) |resource| {
    resource.state = .destroyed;
}
```

The same rule applies to indexes. Do not `contains` and then `get` unless the
two operations are intentionally distinct.

## Allocators

Allocator ownership must be explicit.

- Long-lived runtime tables use the server allocator.
- Temporary allocations inside dispatch paths should be avoided.
- Snapshot and diagnostics code may allocate.
- Every type that owns allocated memory must provide a clear `deinit` path.
- Public C callers must not be required to free Zig allocations unless the C
  API exposes an explicit matching destroy/free function.

Prefer this shape:

```zig
pub fn init(allocator: std.mem.Allocator) Model {
    return .{
        .allocator = allocator,
        // tables...
    };
}

pub fn deinit(model: *Model) void {
    // release tables and owned allocations
}
```

The server allocator is chosen at server creation. For MVP,
`wayplug_server_create()` uses `std.heap.c_allocator`. A future ABI version
may accept a host-supplied allocator interface (`wayplug_allocator_v1`) for
hosts that need to track wayplug allocations.

## Error Handling

Use Zig errors internally where they improve clarity.

At the C ABI boundary, translate errors into C-compatible results:

- `null` for failed object creation
- `false` for failed boolean operations
- negative `int` values for fd/status failures
- explicit diagnostic callbacks or snapshots for detailed errors

Do not expose Zig error unions through the public C header.

Inside protocol callbacks, avoid panics for client-triggered protocol errors.
Record the error, notify the client when appropriate, and route teardown
through operations.

## C ABI Boundary

`include/wayplug.h` is the stable contract.

Rules:

- Only expose opaque handles or versioned structs.
- Include `size` and `version` fields in callback/config structs.
- Never expose Zig-only types.
- Never expose internal table layouts.
- Keep ownership paired: `create/destroy`, `open/close`, `alloc/free`.
- Treat changes to public struct layout as ABI changes unless size/version
  handling preserves compatibility.

`src/c_api.zig` should be the only module that exports public C symbols.
Internal modules should not know about public ABI validation details.

`wayplug_server_destroy(srv)` invalidates every handle the server has
issued, including client displays and resources. The host must stop using
those handles before calling destroy. Destroy is the only guaranteed path
to release server-owned memory; `wayplug_server_close_client_display()`
only tears down a single client.

## Wayland Handles

Wayland pointers are external handles.

Store them in records, index them when needed, but do not treat them as
internal identity. Internal relationships should use logical ids:

```text
ClientId
ResourceId
SurfaceId
BufferId
EmbedId
OutputId
```

Use pointer indexes for lookup:

```text
wl_resource * -> ResourceId
wl_proxy *    -> ResourceId
wl_display *  -> ClientId
```

Use logical ids for relationships:

```text
Embed
  host_parent_surface_id
  plugin_child_surface_id
```

## Protocol Code

Protocol modules should be thin adapters.

They may:

- translate Wayland callback arguments
- validate ownership
- look up upstream handles through queries
- forward simple requests directly
- call operations for lifecycle changes

They must not:

- mutate indexes directly
- own cross-object cleanup policy
- make host policy decisions
- create parallel object graphs outside the model

Direct forwarding is correct for hot paths:

```text
attach
damage
commit
pointer motion
keyboard key
buffer release forwarding
```

Operations are required for lifecycle:

```text
client connected/disconnected
resource created/destroyed
surface role assigned
subsurface relationship created
embed resized/destroyed
protocol error
```

## Tests

Tests use a hybrid layout: `test` blocks at the bottom of each `src/`
file for unit coverage of internal helpers and pure data operations; a
`tests/` directory for integration, cross-domain, and ABI tests.

In-file blocks sit below a clear separator at the end of the file:

```zig
// ===== production code above =====

const std = @import("std");
const testing = std.testing;

test "insert/delete round-trip" {
    // ...
}
```

The separator keeps tests visually grouped after the module body. In-file
tests can reach non-`pub` symbols, which is why this layer carries the
internal-helper coverage.

The `tests/` directory holds:

```text
tests/
  c_abi_smoke.c            ABI surface, compiled via zig cc
  data_tests.zig           cross-module data invariants
  engine_tests.zig         cross-domain lifecycle
  protocol_smoke_tests.zig end-to-end protocol exercise
```

Both layers run under `zig build test`.

Coverage rules:

- Pure data and operations get in-file unit tests.
- C ABI changes update `tests/c_abi_smoke.c`.
- Protocol delegate changes get smoke tests in
  `tests/protocol_smoke_tests.zig` where feasible.
- Teardown logic includes tests for partially-created and already-dead
  objects.

## Comments

Prefer clear names over comments.

Use comments for:

- ownership rules
- subtle Wayland protocol ordering
- why a direct forwarding path deliberately bypasses operations
- ABI compatibility constraints
- teardown order that would otherwise be non-obvious

Avoid comments that restate the code.

## File Size

Soft target: 500 lines per `.zig` file. Hard guideline: 800. A file
crossing 500 should be reviewed for a split; a file at 800 splits.

Concrete rules:

- **One file per Wayland interface in `protocol/`.** Do not bundle
  `seat` + `pointer` + `keyboard` + `touch`, do not bundle
  `xdg_surface` + `xdg_toplevel` + `xdg_popup`. The C++ reference's
  430-line `seatdelegates.cpp` and 550-line `xdgsurfacedelegate.cpp`
  are the failure mode this rule prevents.
- **One file per domain in `engine/`** until it crosses ~500 lines.
  Then promote the domain to a directory: `engine/embed.zig` becomes
  `engine/embed/embed.zig` (facade) plus the sub-files that exposed
  the split.
- **`c_api.zig`** splits by API surface area (`c_api/server.zig`,
  `c_api/embed.zig`) if it grows past the soft target.

Split a module also when it starts mixing domains:

- protocol forwarding plus policy
- data records plus operations
- query helpers plus mutation
- C ABI validation plus protocol implementation

Small focused files keep protocol behavior easier to audit and read
under the context budgets of both human review and AI assistants.
