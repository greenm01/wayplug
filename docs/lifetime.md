# Lifetime Rules

Wayembed is small by design, but Wayland ownership is still sharp. This page
states who owns each handle and when it dies. Treat it as part of the ABI.

## Server

The host owns `wayembed_server *`. It comes from `wayembed_server_create()` and
dies in `wayembed_server_destroy()`.

Destroying the server invalidates every handle the server issued. That includes
plugin displays, client handles, embed handles, and snapshots. Stop using them
first. Then destroy the server.

Wayembed never starts a thread. The host owns the event loop. Call
`wayembed_server_get_fd()`, watch that fd, call `wayembed_server_dispatch()`
when it becomes readable, and call `wayembed_server_flush()` before blocking.

## Threading Model

`wayembed_server` is not thread-safe. The host must serialize every call that
touches the same server: `dispatch()`, `flush()`, client open/close calls,
embed calls, and snapshot calls.

`wayembed_server_dispatch()` may run on any host thread. Callbacks run on the
thread that called `dispatch()`.

A recursive `wayembed_server_dispatch()` call from a callback is ignored. This
prevents re-entry into the Wayland event loop.

This matches libwayland's usual `wl_display` threading model: one connection,
one serialized owner at a time.

## Host Objects

The host owns the real Wayland objects returned by `wayembed_host_interface`:
`wl_compositor`, `wl_subcompositor`, `wl_shm`, `wl_seat`, `xdg_wm_base`, and
`wl_output` metadata. Wayembed borrows those pointers. It does not destroy
them.

Keep those objects alive for the life of the server, or stop exposing the
matching callback before they disappear. A stale host object is a host bug.

## Plugin Displays And Clients

`wayembed_server_open_client_display()` returns a plugin-side `wl_display *`.
The host passes that display to the plugin. The host closes it with
`wayembed_server_close_client_display()`, or lets `wayembed_server_destroy()`
tear it down.

`wayembed_server_open_client_fd()` returns a plugin-side connection fd and
stores the matching client handle in `out_client`. The caller owns the fd.
Pass it to the plugin process, close any host-side duplicate when the handoff
is done, and keep dispatching the wayembed server. A remote close turns into
`on_client_closed` during dispatch.

`wayembed_server_close_client()` closes a live client opened through either
path. For fd-opened clients, it closes wayembed's server-side state. It does
not close the raw fd returned to the host.

`wayembed_client *` is an opaque handle. The host receives it in callbacks.
For fd-opened clients, `wayembed_server_open_client_fd()` also returns it
through `out_client`. The handle stays valid until `on_client_closed` returns,
or until `wayembed_server_destroy()` starts. After that, the handle is dead.

Do not store a client handle past close. Store it only to attach a new embed
while the client lives.

## Surfaces, Buffers, And Resources

Plugin-created `wl_surface` and `wl_buffer` objects belong to the plugin
protocol stream. Wayembed tracks them so it can forward requests and tear them
down in order.

The host sees a plugin child surface through `on_surface_created`. That
callback fires for every plugin `wl_compositor.create_surface()` request, after
wayembed has created the upstream surface and model row. It fires before the
first commit and before later batched requests in the same dispatch. The host
may pass that pointer to `wayembed_embed_attach()` during the callback. It must
not destroy that surface.

Host parent surfaces stay host-owned. Wayembed borrows the parent pointer when
it creates the embed wiring. Keep the parent alive until the embed dies or the
client closes.

## Embeds

`wayembed_embed_attach()` starts one embedded session for the client and returns
a server-owned `wayembed_embed *`. A client can have one active embed.
`wayembed_embed_resize()` targets that embed handle.

Embed handles are valid until `on_embed_destroyed` returns, or until server
destroy. `wayembed_embed_id()` returns a stable numeric id for logs. The id is
not a handle.

`on_embed_destroyed` fires before `on_client_closed` when client teardown
destroys an active embed.

If the plugin destroys the embedded child surface without closing the client,
wayembed destroys that embed and fires `on_embed_destroyed`. The client may
create another surface and attach a new embed later.

## Snapshots

`wayembed_server_snapshot()` returns a copy. The caller owns it and must call
`wayembed_snapshot_free()`.

Snapshots do not update after creation. They remain valid until freed, even if
the server changes. Destroying the server invalidates all server-issued handles,
so free snapshots before server destroy.

## Adapter Handoffs

`wayembed_adapter_handoff` and `wayembed_adapter_resize` are caller-owned
structs. Wayembed fills or validates them. It does not keep pointers to them.

The display inside a handoff follows the plugin display rules. The token string
points to static library storage. The caller must not free it.

## Callback Re-Entry

Callbacks fire from `wayembed_server_dispatch()`.

Allowed same-server calls inside callbacks:

| Callback | Allowed same-server calls |
| --- | --- |
| `on_surface_created` | `wayembed_embed_attach()` for the surface passed to the callback |
| `on_embed_mapped`, `on_embed_resized`, `on_embed_destroyed` | handle inspectors such as `wayembed_embed_id()` and `wayembed_embed_client()` |
| `on_client_connected`, `on_client_closed`, `on_protocol_error` | no same-server calls |

Other same-server calls from callbacks are unsupported. A recursive
`wayembed_server_dispatch()` call is ignored. Host callbacks may still make
Wayland calls on the host's own upstream connection.

## Teardown Order

When a client closes, wayembed destroys its state in this order:

1. embeds;
2. plugin child surfaces;
3. buffers and frame callbacks;
4. remaining resources;
5. resource indexes;
6. Wayland client and optional display handles;
7. socket fds, except raw fds already handed to the host;
8. the client row.

This keeps children ahead of parents. It also gives hosts a fixed order for
logs and cleanup.
