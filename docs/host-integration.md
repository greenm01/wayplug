# Host Integration Walkthrough

This document shows the host calls needed to embed a Wayland-native plugin
editor. The examples are Carla-shaped: a Qt audio plugin host with its own
Wayland connection and an editor area inside a host window.

The public ABI in [../include/wayembed.h](../include/wayembed.h) is the source
of truth. If this walkthrough is awkward to write, the ABI needs work.

## Feature Discovery

Hosts can ask which protocol delegates the library was built with before they
create a server.

```c
wayembed_features features = {
    .size = sizeof(features),
    .version = WAYEMBED_ABI_VERSION,
};

if (!wayembed_get_features(&features)) {
    return false;
}

bool can_embed_surfaces =
    (features.flags & WAYEMBED_FEATURE_COMPOSITOR) &&
    (features.flags & WAYEMBED_FEATURE_SUBCOMPOSITOR) &&
    (features.flags & WAYEMBED_FEATURE_SURFACE) &&
    (features.flags & WAYEMBED_FEATURE_SHM_BUFFER) &&
    (features.flags & WAYEMBED_FEATURE_EMBED_SESSION);
```

Feature flags report compiled support. Host callbacks still decide which
Wayland globals a server advertises to a plugin display.

| Flag | Meaning |
| --- | --- |
| `WAYEMBED_FEATURE_COMPOSITOR` | `wl_compositor` bind and surface creation |
| `WAYEMBED_FEATURE_SUBCOMPOSITOR` | host-side subsurface wiring |
| `WAYEMBED_FEATURE_SURFACE` | `wl_surface` forwarding |
| `WAYEMBED_FEATURE_SHM_BUFFER` | `wl_shm`, pools, and buffers |
| `WAYEMBED_FEATURE_EMBED_SESSION` | `wayembed_embed *` attach and resize |
| `WAYEMBED_FEATURE_SEAT` | `wl_seat` bind |
| `WAYEMBED_FEATURE_POINTER` | pointer forwarding with coordinate translation |
| `WAYEMBED_FEATURE_KEYBOARD` | keyboard forwarding from the host seat |
| `WAYEMBED_FEATURE_TOUCH` | touch forwarding with coordinate translation |
| `WAYEMBED_FEATURE_OUTPUT` | initial `wl_output` metadata |
| `WAYEMBED_FEATURE_XDG_SHELL` | delegated XDG shell objects |
| `WAYEMBED_FEATURE_CLIENT_FD` | raw client fd handoff for out-of-process plugins |

## Shape of a Session

```text
host                         wayembed                         plugin
 | create server                |                                |
 |----------------------------->|                                |
 | open client display          |                                |
 |----------------------------->|                                |
 | wl_display *                 |                                |
 |<-----------------------------|                                |
 | hand display to plugin       |                                |
 |                              |                                |
 |                              |     bind wl_compositor         |
 |                              |<-------------------------------|
 |                              |     create wl_surface          |
 |                              |<-------------------------------|
 | on_surface_created           |                                |
 |<-----------------------------|                                |
 | attach embed synchronously   |                                |
 |----------------------------->|                                |
 |                              |     attach buffer, commit      |
 |                              |<-------------------------------|
 | resize embed                 |                                |
 |----------------------------->|                                |
 |                              |     set subsurface position    |
 |                              |------------------------------->|
 |                              |                                |
 |                              |     disconnect or destroy UI   |
 |                              |<-------------------------------|
 | on_embed_destroyed           |                                |
 |<-----------------------------|                                |
 | on_client_closed             |                                |
 |<-----------------------------|                                |
```

## Host Interface

The host provides upstream globals and lifecycle callbacks through
`wayembed_host_interface`. Null function pointers disable optional globals or
notifications.

```c
struct carla_host {
    struct wl_display *upstream_display;
    struct wl_compositor *upstream_compositor;
    struct wl_subcompositor *upstream_subcompositor;
    struct wl_shm *upstream_shm;
    struct wl_seat *upstream_seat;
    struct xdg_wm_base *upstream_xdg_wm_base;

    struct wl_surface *editor_parent_surface;
    wayembed_embed *active_embed;
    int editor_x_in_window;
    int editor_y_in_window;
};

static bool get_subsurface_offset(void *u, int32_t *x, int32_t *y,
                                  struct wl_display *display,
                                  struct wl_surface *parent,
                                  struct wl_surface *child) {
    (void)display; (void)parent; (void)child;
    struct carla_host *h = u;
    *x = h->editor_x_in_window;
    *y = h->editor_y_in_window;
    return true;
}
```

`display` is the plugin-side `wl_display *` for in-process clients. It is null
for clients opened with `wayembed_server_open_client_fd()`. Use
`wayembed_client *` as the stable key for per-plugin state.

The surface callback is where embedded mode starts:

```c
static void on_surface_created(void *u, wayembed_client *client,
                               struct wl_surface *child) {
    struct carla_host *h = u;
    wayembed_embed_attach_info info = {
        .size = sizeof(info),
        .version = WAYEMBED_ABI_VERSION,
        .client = client,
        .parent_surface = h->editor_parent_surface,
        .child_surface = child,
    };

    wayembed_embed *embed = NULL;
    uint32_t status = wayembed_embed_attach(&info, &embed);
    if (status != WAYEMBED_EMBED_STATUS_OK) {
        carla_log_embed_attach_failure(status);
        return;
    }

    h->active_embed = embed;
}
```

`on_surface_created` fires inline during `wl_compositor.create_surface()`,
after wayembed creates the upstream surface and records it in the model. The
callback fires before later batched requests on that same plugin dispatch can
run. A host may call `wayembed_embed_attach()` synchronously inside this
callback. Other same-server calls from callbacks remain unsupported.

Embed callbacks receive the server-owned embed handle:

```c
static void on_embed_mapped(void *u, wayembed_embed *embed) {
    fprintf(stderr, "embed mapped: id=%u\n", wayembed_embed_id(embed));
}

static void on_embed_resized(void *u, wayembed_embed *embed,
                             int32_t width, int32_t height) {
    (void)u; (void)embed; (void)width; (void)height;
}

static void on_embed_destroyed(void *u, wayembed_embed *embed) {
    struct carla_host *h = u;
    if (h->active_embed == embed) {
        h->active_embed = NULL;
    }
}
```

`wayembed_embed *` is valid until `on_embed_destroyed` returns, or until
`wayembed_server_destroy()` invalidates all server handles.

## Server And Event Loop

```c
wayembed_server *server = wayembed_server_create(&host_iface, NULL);
if (!server) {
    return -1;
}
```

wayembed never starts a thread or owns a poll loop. The host watches
`wayembed_server_get_fd(server)`, calls `wayembed_server_dispatch(server)` when
the fd is readable, and calls `wayembed_server_flush(server)` before blocking.

`wayembed_server_dispatch()` fires callbacks before it returns. Host callbacks
may issue Wayland calls on the host's own upstream connection.

## Opening A Plugin Display

When the plugin asks for a Wayland UI, open a plugin-side display and pass it
through the plugin format glue.

```c
struct wl_display *plugin_display =
    wayembed_server_open_client_display(server);

if (!plugin_display) {
    return CLAP_WINDOW_API_FAILED;
}

clap_window_t window = {
    .api = CLAP_WINDOW_API_WAYLAND,
    .wayland = plugin_display,
};
plugin_gui->set_parent(plugin, &window);
plugin_gui->show(plugin);
```

The plugin sees a normal `wl_display *`: bind globals, create a surface, attach
buffers, and commit.

## Opening A Plugin Fd

For an out-of-process plugin, open a client fd instead of a client display.

```c
wayembed_client *plugin_client = NULL;
int plugin_fd = wayembed_server_open_client_fd(server, &plugin_client);

if (plugin_fd < 0 || !plugin_client) {
    return CLAP_WINDOW_API_FAILED;
}
```

The host owns `plugin_fd`. Pass it through the plugin format's process or IPC
glue, then close the fd in the host when that handoff is done. If the plugin
closes its end or exits, the host must dispatch the wayembed server so
`on_client_closed` can fire.

`plugin_client` is live as soon as the call succeeds. Use it to key host-side
state for the process you launch. `on_client_connected` still fires from
`wayembed_server_dispatch()`, which keeps callback timing the same as the
display path.

To stop a fd-opened client from the host side:

```c
wayembed_server_close_client(server, plugin_client);
close(plugin_fd);
wayembed_server_dispatch(server);
```

## Embedded Surface Contract

Embedded mode is for a plain plugin `wl_surface`. wayembed turns that surface
into a subsurface of the host parent surface.

`wayembed_embed_attach()` immediately:

- creates the upstream `wl_subsurface`;
- assigns the child surface the subsurface role;
- positions it with `get_subsurface_offset`;
- creates one active `wayembed_embed *` for the client;
- queues `on_embed_mapped`.

A client may create multiple surfaces, but it may have only one active embed.
If the plugin destroys the embedded child surface, wayembed destroys the embed
and fires `on_embed_destroyed`. The same client may later create another
surface and attach a new embed.

Attach status codes tell the host what to do:

| Status | Host action |
| --- | --- |
| `WAYEMBED_EMBED_STATUS_OK` | Store the returned embed handle. |
| `WAYEMBED_EMBED_STATUS_INVALID_ARGUMENT` | Fix the host call site. |
| `WAYEMBED_EMBED_STATUS_CLIENT_CLOSING` | Stop work for this client. |
| `WAYEMBED_EMBED_STATUS_ALREADY_EMBEDDED` | Reuse or destroy the active embed first. |
| `WAYEMBED_EMBED_STATUS_UNKNOWN_SURFACE` | Ignore this surface or wait for the next one. |
| `WAYEMBED_EMBED_STATUS_SURFACE_HAS_ROLE` | The plugin made the surface a toplevel, popup, cursor, or subsurface first. |
| `WAYEMBED_EMBED_STATUS_UNSUPPORTED` | The host did not expose `wl_subcompositor`. |
| `WAYEMBED_EMBED_STATUS_UPSTREAM_FAILED` | Log diagnostics and fail the plugin UI. |
| `WAYEMBED_EMBED_STATUS_UNKNOWN_EMBED` | Drop the stale embed handle. |

## Resize

Resize targets the embed handle, not the client.

```c
void carla_on_window_resize(struct carla_host *h,
                            int32_t width,
                            int32_t height) {
    if (!h->active_embed) {
        return;
    }

    uint32_t status = wayembed_embed_resize(h->active_embed, width, height);
    if (status != WAYEMBED_EMBED_STATUS_OK) {
        carla_log_embed_resize_failure(status);
    }
}
```

Width and height must be non-negative. Zero is accepted. Resize stores the new
size in the embed record and reapplies the current subsurface offset.

## Input, Output, And XDG

Keyboard focus is compositor-driven in this phase. If the host exposes
`wl_seat`, wayembed forwards pointer, keyboard, and touch objects from the host
seat to the plugin. Pointer and touch coordinates are translated through
`get_subsurface_offset`. There is no host-synthesized keyboard focus API yet.

`wl_output` is sent from `get_output_info()` when the plugin binds the output.
Use it for initial scale and mode data. Dynamic output changes are outside this
phase.

XDG shell is delegated for plugin-created popups, menus, dialogs, or floating
windows. It is not the embedding primitive. The embedded editor surface must
stay role-less until `wayembed_embed_attach()` assigns the subsurface role. A
surface that becomes `xdg_toplevel` or `xdg_popup` cannot also become the
embedded surface.

## Teardown

When the plugin disconnects, wayembed:

1. releases role/helper objects before parent surfaces;
2. destroys active embeds and fires `on_embed_destroyed`;
3. releases plugin surfaces, buffers, and resources;
4. fires `on_client_closed`;
5. releases the client row.

Destroying the server invalidates plugin displays, client handles, embed
handles, and snapshots. For the full ownership contract, see
[Lifetime Rules](lifetime.md).

## Common Pitfalls

- Do not wait for the first commit before attaching. Attach in
  `on_surface_created`.
- Do not attach a surface after the plugin gives it an XDG role.
- Do not store `wayembed_client *` after `on_client_closed`.
- Do not store `wayembed_embed *` after `on_embed_destroyed`.
- Do not call `wayembed_embed_resize()` with a client handle.
- Do not expose `WAYEMBED_FEATURE_*` support unless the matching host callback
  also returns the real Wayland object the plugin needs.
