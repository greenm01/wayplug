# Logging

wayplug does not emit log lines. It surfaces structured lifecycle events
through the `wayplug_host_interface` callback table. Logging is a host
responsibility.

This keeps the library free of log-format opinions and output-fd assumptions,
and avoids adding overhead to paths where the host has no interest in logging.

Protocol hot paths — `wl_surface.attach`, `damage`, `commit`, pointer motion,
keyboard events — stay direct and produce no notifications. Lifecycle
boundaries (client connect/close, surface creation, protocol errors) surface
as callbacks.

## Current Callback Surface

The `wayplug_host_interface` struct carries lifecycle and diagnostics
callbacks. They fire synchronously from inside `wayplug_server_dispatch()`
after the effect queue drains. A null function pointer is a no-op.

```c
void (*on_client_connected)(void *userdata, wayplug_client *client);
```

Fires when a plugin opens a display via `wayplug_server_open_client_display`.
`client` is valid until `on_client_closed` fires for the same client.

```c
void (*on_surface_created)(void *userdata,
                           wayplug_client *client,
                           struct wl_surface *plugin_child_surface);
```

Fires when the plugin calls `wl_compositor.create_surface`. The host
typically calls `wayplug_embed_attach` here to parent the surface.

```c
void (*on_client_closed)(void *userdata, wayplug_client *client);
```

Fires after wayplug completes the full client teardown sequence (see
[Architecture § Teardown Order](architecture.md#teardown-order)). After this
callback returns, `client` is invalid and must not be dereferenced.

```c
void (*on_protocol_error)(void *userdata,
                          wayplug_client *client,
                          uint32_t code);
```

Fires when an internal `protocol_error` effect is queued for a client.
`code` is the Wayland protocol error code recorded by the delegate.
Registry bind validation uses this path too: invalid global bind versions
surface as `WL_DISPLAY_ERROR_INVALID_METHOD`, and unexpected missing host
objects during bind surface as `WL_DISPLAY_ERROR_IMPLEMENTATION`.

```c
void (*on_embed_mapped)(void *userdata, uint32_t embed_id);
```

Fires after `wayplug_embed_attach` establishes the parent/child/subsurface
relationship. `embed_id` is stable for the server lifetime and is not reused.

```c
void (*on_embed_resized)(void *userdata,
                         uint32_t embed_id,
                         int32_t width,
                         int32_t height);
```

Fires when `wayplug_embed_resize` updates an existing embed.

```c
void (*on_embed_destroyed)(void *userdata, uint32_t embed_id);
```

Fires before the owning client's `on_client_closed` callback when teardown
destroys that client's embeds.

### Constraints

- Callbacks return `void`. They report; they do not gate. Policy decisions
  run in the engine before the notification fires.
- `on_surface_created` may call `wayplug_embed_attach` on the same server to
  establish the embedded editor session. Other same-server calls from
  callbacks are undefined.
- Callbacks may issue Wayland calls on the host's own upstream connection.
- The engine drains its effect queue at the end of each dispatch tick, after
  every protocol callback for that tick has run. See [Architecture §
  Host Notifications](architecture.md#host-notifications).

## Snapshot API

The public C ABI exposes an allocating diagnostic snapshot:

```c
wayplug_snapshot *wayplug_server_snapshot(wayplug_server *server);
bool wayplug_snapshot_get_counts(const wayplug_snapshot *snapshot,
                                 wayplug_snapshot_counts *counts);
void wayplug_snapshot_free(wayplug_snapshot *snapshot);
```

Snapshots are point-in-time copies. Later server operations do not mutate an
existing snapshot. The caller owns each snapshot and must release it with
`wayplug_snapshot_free`. The current C view exposes table counts; record-level
iteration is intentionally left for a later diagnostic schema.

## Stable Identifiers for Log Lines

Use `wayplug_client *` as the stable key in log output. It is an opaque
handle that uniquely identifies a client within the server's lifetime and
does not change addresses while the client is alive.

Prefer it over `wl_display *` or raw file descriptor numbers, which are not
stable across server restarts or between runs.

```c
static void on_client_connected(void *u, wayplug_client *client) {
    fprintf(stderr, "wayplug: client connected %p\n", (void *)client);
}

static void on_client_closed(void *u, wayplug_client *client) {
    fprintf(stderr, "wayplug: client closed %p\n", (void *)client);
}
```

Both callbacks receive the same `client` pointer, so these two log lines
can be correlated across a session. Use this pointer as the anchor when
comparing logs across runs of the same session type.

## Host Logging Patterns

Minimal logging for a production host — connect, surface, and close events:

```c
static void on_client_connected(void *u, wayplug_client *client) {
    struct my_host *h = u;
    fprintf(h->log, "plugin connected: client=%p\n", (void *)client);
}

static void on_surface_created(void *u, wayplug_client *client,
                               struct wl_surface *child) {
    struct my_host *h = u;
    fprintf(h->log, "plugin surface: client=%p surface=%p\n",
            (void *)client, (void *)child);
    wayplug_embed_attach(client, h->editor_parent_surface, child);
}

static void on_client_closed(void *u, wayplug_client *client) {
    struct my_host *h = u;
    fprintf(h->log, "plugin disconnected: client=%p\n", (void *)client);
    my_host_clear_editor(h);
}
```

The surface pointer in `on_surface_created` is a host-compositor handle —
it is stable for protocol use but should not be the primary log key since
it is not exposed by other callbacks. Use `client` as the correlation key.

## Diagnostics Effect Surface

The internal effect queue (see [DOD § Effects](dod.md#effects)) already
tracks embed lifecycle and diagnostics:

```
embed_mapped(embed_id)
embed_resized(embed_id, width, height)
embed_destroyed(embed_id)
protocol_error(client_id, code)
diagnostics_dirty
```

`protocol_error` is surfaced through `on_protocol_error`. Embed lifecycle
effects are surfaced through the embed callbacks, keyed on embed id (a stable
`uint32_t` that is not reused in a server's lifetime). For a normal plugin
disconnect, `embed_destroyed` is delivered before `client_closed` for the
owning client.

## Developer and Agent Debugging Evidence

When debugging protocol, lifecycle, or compositor-specific bugs, gather
evidence that can be compared across runs. This matches [AGENTS.md §
Debugging Evidence](../AGENTS.md#debugging-evidence).

**State snapshots** — take a snapshot of callback-visible state before and
after the reproducing step. Use `wayplug_server_snapshot` plus
`wayplug_snapshot_get_counts` to record current table counts. Pair these with
host-tracked details such as surfaces attached or embeds active until
record-level snapshot iteration lands.

**Client handle** — the `wayplug_client *` value is the most useful
cross-run key. It is the anchor that ties connect, surface-created, and close
events together.

**Embed ids** — embed ids (`uint32_t`) are the stable key for the embed's
full lifecycle (mapped → resized → destroyed). Record these alongside the
client handle.

**Protocol error records** — `on_protocol_error` carries the client handle
and Wayland error code. Log both so protocol failures can be correlated with
connect, surface-created, and close events.

**Client connect/disconnect logs** — the three current callbacks already
bracket the full client lifecycle. Logging all three is sufficient to trace
connect, surface, and teardown ordering.

**Compositor name and protocol globals** — record `wl_display_get_name` on
the upstream display and the globals advertised by `wl_registry` at startup.
Compositor-specific behavior (KWin vs. Mutter vs. Weston) often shows up as
a difference in which globals are advertised or in the exact protocol path a
delegate takes.

**Exact Wayland protocol path** — when a bug is protocol-specific, name the
delegate file and callback involved, e.g.:

```
protocol/compositor.zig → wl_compositor_create_surface listener
engine/surface.zig      → surfaceCreate op
effects queue           → surface_created effect
host callback           → on_surface_created
```

This lets a second reader reproduce the code path without grepping.

Do not delete generated diagnostic output as cleanup unless the task
specifically requires it. Lifecycle and teardown bugs are often only
reproducible with a specific compositor and are best diagnosed from logs
taken at the time.
