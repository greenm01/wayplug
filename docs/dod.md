# Data-Oriented Design

`wayembed` should use a data-oriented runtime built from plain types, indexed
state, explicit mutation operations, query facades, systems for policy, and
thin protocol adapters.

The goal is not to turn Wayland into an Elm/TEA application. Wayland already
has a protocol object model. `wayembed` should keep simple request/event
forwarding direct, while using a data model for ownership, lifecycle, cleanup,
diagnostics, and tests.

## Core Rule

Separate data from code.

The `data/` layer defines records and owns storage. The `engine/` layer holds
code that operates on the data — mutation, queries, and policy live together
per domain, in one file. Protocol modules translate Wayland callbacks and
either forward directly or call into the engine.

```text
protocol callback
        |
        +-- simple protocol forwarding
        |
        +-- lifecycle or ownership change
                |
                v
             operation
                |
                v
          indexed data model
```

Raw Wayland pointers are fields in records. They are not the source of truth for
internal relationships.

## Module Layout

Two directories carry the model: `data/` holds the schema and storage,
`engine/` holds the code that operates on it. Each engine file is sliced by
domain rather than by mutation/query/policy — the boundary lives in
function naming inside the file, not in the directory tree.

```text
src/data/
  types.zig         records, ids, enums, flags
  model.zig         EntityManagers, indexes, id counters
  snapshot.zig      generic snapshot walker
  invariants.zig    generic invariant walker

src/engine/
  engine.zig        facade
  client.zig        ops, queries, policy for clients
  resource.zig
  surface.zig
  buffer.zig
  embed.zig
  output.zig
  effects.zig       per-dispatch effect queue

src/protocol/
  server.zig
  registry.zig
  compositor.zig
  surface.zig
  subcompositor.zig
  shm.zig
  seat.zig
  output.zig
```

`engine/engine.zig` is the facade. Protocol and `c_api.zig` go through it
rather than reaching into `data/` directly. The protocol layer keeps direct
forwarding for hot paths; lifecycle and mutation go through the engine.

## Types

The `types` layer should be boring. It should describe the model without
implementing the model's behavior.

```zig
pub const ClientId = enum(u32) { null_id = 0, _ };
pub const ResourceId = enum(u32) { null_id = 0, _ };
pub const SurfaceId = enum(u32) { null_id = 0, _ };
pub const BufferId = enum(u32) { null_id = 0, _ };
pub const EmbedId = enum(u32) { null_id = 0, _ };
pub const OutputId = enum(u32) { null_id = 0, _ };
```

```zig
pub const Client = struct {
    id: ClientId,
    state: ClientState,
    server_fd: i32,
    client_fd: i32,
    wl_client: ?*wl_client,
    wl_display: ?*wl_display,
};
```

```zig
pub const Resource = struct {
    id: ResourceId,
    client_id: ClientId,
    kind: ResourceKind,
    state: ResourceState,
    wl_resource: ?*wl_resource,
    upstream_proxy: ?*wl_proxy,
    generation: u32,
};
```

```zig
pub const Embed = struct {
    id: EmbedId,
    client_id: ClientId,
    state: EmbedState,
    host_parent_surface_id: SurfaceId,
    plugin_child_surface_id: SurfaceId,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};
```

The records should not grow methods like `surface.attach()` or
`client.destroyAllResources()`. Those belong in protocol delegates and ops.

## Model

The model should be table-oriented. It holds the server allocator. Every
long-lived table and index uses that allocator. Ops and queries read the
allocator from the model rather than taking it as a parameter.

```zig
pub const WayembedModel = struct {
    counters: IdCounters,

    clients: EntityManager(ClientId, Client),
    resources: EntityManager(ResourceId, Resource),
    surfaces: EntityManager(SurfaceId, Surface),
    buffers: EntityManager(BufferId, Buffer),
    embeds: EntityManager(EmbedId, Embed),
    outputs: EntityManager(OutputId, Output),

    client_by_wl_client: HashMap(*wl_client, ClientId),
    client_by_display: HashMap(*wl_display, ClientId),
    resource_by_wl_resource: HashMap(*wl_resource, ResourceId),
    resource_by_upstream_proxy: HashMap(*wl_proxy, ResourceId),
    surface_by_resource: HashMap(ResourceId, SurfaceId),
    buffer_by_resource: HashMap(ResourceId, BufferId),
    embed_by_child_surface: HashMap(SurfaceId, EmbedId),
    embed_by_parent_surface: HashMap(SurfaceId, EmbedId),
    resources_by_client: HashMap(ClientId, ArrayList(ResourceId)),
};
```

The model uses dense entity tables plus relationship indexes. External handles
map into logical ids, and logical ids describe relationships.

## Entity Manager

Use dense storage where practical.

```text
EntityManager(T)
  data[]          dense records
  index           Id -> dense index
```

Deletion may use swap-and-pop internally. Logical ids remain stable. Callers
must not depend on physical array position.

The entity manager should provide only low-level CRUD:

```text
insert(record)
delete(id)
contains(id)
get(id)
getMutable(id)
items()
```

It should not understand Wayland, embeds, clients, or cleanup policy.

## ID Generation

Use explicit logical ids. Id `0` is null/invalid.

```text
ClientId
ResourceId
SurfaceId
BufferId
EmbedId
OutputId
```

Counters increment before issue. If a counter wraps to zero, treat that as an
internal fatal error. Do not reuse ids during the lifetime of a server unless a
future generation scheme makes reuse explicit.

## Indexes

Hot lookups should use indexes instead of scans.

```text
wl_client *    -> ClientId
wl_display *   -> ClientId
wl_resource *  -> ResourceId
wl_proxy *     -> ResourceId
ResourceId     -> SurfaceId
ResourceId     -> BufferId
SurfaceId      -> EmbedId
ClientId       -> ResourceId list
```

Indexes are owned by the state layer. They are maintained by ops. Protocol
delegates should ask the facade for the ids or upstream handles they need.

## Iterators

Iterators expose traversal without exposing storage internals.

Examples:

```text
clientsWithId()
resourcesWithId()
resourcesForClient(client_id)
surfacesForClient(client_id)
embedsForClient(client_id)
outputsWithId()
```

Hot dispatch-time paths should prefer iterators, ids, or borrowed views over
allocation-returning helpers.

Allocation-returning helpers are acceptable for snapshots, diagnostics, and
tests.

Iterators yield borrowed views. They do not allocate. Any operation that
mutates the underlying table invalidates outstanding iterators on that
table. Callers must not hold an iterator across an ops call. Iteration order
is ascending logical id.

## Queries

Queries answer domain questions. They should not mutate state.

Examples:

```text
clientForDisplay(display)
clientForWlClient(wl_client)
resourceForWlResource(resource)
resourceForUpstreamProxy(proxy)
surfaceForResource(resource_id)
bufferForResource(resource_id)
embedForChildSurface(surface_id)
embedForParentSurface(surface_id)
upstreamProxyForResource(resource_id)
resourceBelongsToClient(resource_id, client_id)
```

Queries hide table/index details from protocol and systems code.

## Operations

All cross-table mutation goes through operation functions. They live in the
relevant `engine/<domain>.zig` file alongside that domain's queries and
policy. Naming: prefer verb-first (`clientCreate`, `embedAttachChild`) so a
grep for `pub fn .*Create\|.*Destroy\|.*Attach` surfaces every mutation.

```text
clientCreate()
clientDestroy()
resourceCreate()
resourceDestroy()
surfaceCreate()
surfaceDestroy()
bufferCreate()
bufferDestroy()
embedCreate()
embedAttachChild()
embedResize()
embedDestroy()
protocolError()
```

Operations are responsible for maintaining indexes and relationships.

Example: resource creation.

```text
resourceCreate(client_id, kind, wl_resource, upstream_proxy)
  id = nextResourceId()
  insert Resource
  resource_by_wl_resource[wl_resource] = id
  resource_by_upstream_proxy[upstream_proxy] = id
  resources_by_client[client_id].append(id)
```

Example: client destruction.

```text
clientDestroy(client_id)
  mark client closing
  destroy embeds owned by client
  destroy child surfaces
  destroy buffers and callbacks
  destroy remaining resources
  remove resource indexes
  close Wayland client/display/fds
  remove client indexes
  mark client dead
```

This is where the data-oriented model matters most. Teardown must be
centralized, because Wayland object destruction can arrive from many
directions.

## Systems

Policy and behavior over the model live as functions inside the same
`engine/<domain>.zig` file as the domain's ops. No separate `systems/`
directory: an embed resize decision and the `embedResize` mutation it
triggers share types, share indexes, and read together.

Domain-level concerns:

- lifecycle cleanup (in `engine/client.zig`)
- embed resize handling (`engine/embed.zig`)
- input coordinate translation (`engine/embed.zig` or a dedicated
  `engine/input.zig` once seat support lands)
- popup/toplevel policy (`engine/surface.zig`)
- diagnostics (`engine/engine.zig` or a dedicated diagnostics module)

Policy functions read through queries and mutate through ops. They do not
own protocol resources independently.

Example policy questions:

```text
mayClientCreateToplevel(client_id)
mayClientCreatePopup(client_id, parent_surface_id)
effectiveEmbedSize(embed_id)
translatedPointerPosition(embed_id, x, y)
disconnectPolicy(client_id)
```

## Protocol Adapters

Protocol modules are adapters around libwayland callbacks.

They should:

- translate Wayland callback arguments into ids and handles
- validate resource ownership
- forward simple protocol requests directly
- call operations for lifecycle changes
- report protocol errors through the state layer

They should not:

- own cross-object lifecycle state
- scan global tables directly
- make host policy decisions
- mutate indexes by hand

## Direct Forwarding Path

Simple hot-path requests should stay direct.

```text
wl_surface.attach
  resourceForWlResource(buffer)
  upstreamProxyForResource(buffer_resource_id)
  wl_surface_attach(upstream_surface, upstream_buffer, x, y)
```

```text
wl_surface.damage
  wl_surface_damage(upstream_surface, x, y, w, h)
```

```text
wl_surface.commit
  wl_surface_commit(upstream_surface)
```

```text
wl_pointer.motion event
  translate coordinates if needed
  wl_pointer_send_motion(plugin_pointer_resource, ...)
```

These should not go through a `Msg -> update -> Cmd` loop.

## Operation Path

Lifecycle-sensitive callbacks should go through ops.

```text
wl_compositor.create_surface
  create upstream wl_surface
  resourceCreate(kind = surface)
  surfaceCreate(resource_id)
```

```text
wl_subcompositor.get_subsurface
  validate child and parent surfaces
  create upstream wl_subsurface
  resourceCreate(kind = subsurface)
  embedAttachChild(parent_surface_id, child_surface_id)
```

```text
wl_resource destroy
  resourceDestroy(resource_id)
```

```text
client disconnect
  clientDestroy(client_id)
```

## Effects

The runtime can separate model updates from host-visible notifications and
deferred Wayland work with a lightweight effect layer.

Examples:

```text
EffectClientClosed(client_id)
EffectEmbedMapped(embed_id)
EffectEmbedResized(embed_id, width, height)
EffectProtocolError(client_id, code)
EffectDiagnosticsDirty
```

Do not overuse effects for ordinary forwarding. They are useful when an
operation should notify the host, update diagnostics, or schedule cleanup.

Ops append effects to a per-dispatch queue. The engine drains the queue at
the end of `dispatch()`, after every protocol callback for that tick has
run. Host-visible effects fire as `wayembed_host_interface` callbacks.
Diagnostic effects set snapshot dirty bits. Effects fire in append order
and must not call back into ops.

## Invariants

Add invariant checks early. They will catch the most expensive bugs.

Examples:

- every resource's `client_id` exists
- every `wl_resource *` index points to an existing resource
- every upstream proxy index points to an existing resource
- every surface references an existing surface resource
- every buffer references an existing buffer resource
- every embed references existing parent and child surfaces
- every client resource list references resources owned by that client
- no destroyed resource remains in any index

Invariant checks should be cheap enough for tests and diagnostics, not
necessarily for every dispatch in production.

`data/invariants.zig` is comptime-generic over the model's tables. Per-table
checks (no holes, no destroyed entries in indexes, dense/sparse mapping
consistent) come for free when a new record type is added to `model.zig`.
Relationship invariants — anything that crosses tables — stay explicit,
because they encode domain knowledge `@typeInfo()` cannot infer.

## Snapshots

Diagnostics should expose snapshots instead of raw internal tables.

```text
ServerSnapshot
  clients
  embeds
  resource_counts_by_kind
  outputs
  protocol_errors
```

Snapshots are useful for:

- tests
- host diagnostics
- logging plugin disconnects
- debugging cleanup order
- reproducing compositor-specific behavior

Snapshots may allocate. Hot protocol paths should not.

A snapshot is caller-owned. The snapshot function allocates with the server
allocator and returns a value the caller releases with `snapshotFree()`. The
C ABI exposes a matching `wayembed_snapshot_free()`. A snapshot is a copy;
subsequent ops do not invalidate it.

`data/snapshot.zig` is comptime-generic. It walks every table in `model.zig`
using `@typeInfo()` and copies records into the snapshot structure. New
record types appear in the snapshot automatically. Hand-written conversions
are only needed for fields that should be redacted or transformed at the
boundary.

## Good Split

Direct delegate path:

```text
attach
damage
commit
frame callback request
pointer motion
keyboard key
buffer release forwarding
```

DOD operation path:

```text
client connected
client disconnected
resource created
resource destroyed
surface role assigned
subsurface relationship created
embed mapped/resized/destroyed
protocol error
parent surface withdrawn
```

This keeps the protocol layer fast and familiar while giving the library a
coherent internal model for the parts most likely to break.

## Non-Goal

`wayembed` should not become a full Elm/TEA runtime.

Avoid this for every request:

```text
Msg -> update(Model) -> Cmd -> Wayland call
```

That pattern is too indirect for protocol forwarding. The useful part is
the separation between `data/` (records, storage, indexes) and `engine/`
(operations, queries, policy), and between both of those and the protocol
adapters. Apply that separation where it clarifies ownership and cleanup.
