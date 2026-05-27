# Host Integration Walkthrough

This document shows the host calls needed to embed a Wayland-native plugin
editor. The examples are Carla-shaped: a Qt audio plugin host with its own
Wayland connection and an editor area inside a host window.

The public ABI in [../include/wayembed.h](../include/wayembed.h) and
[../include/wayembed_adapters.h](../include/wayembed_adapters.h) is the
source of truth. If this walkthrough is awkward to write, the ABI needs work.

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
after wayembed creates the upstream surface and records it in the model. It
fires for every plugin surface, before the first commit, and before later
batched requests on that same plugin dispatch can run. The plugin has not
attached a buffer or committed the surface when this callback runs. A host may
call `wayembed_embed_attach()` synchronously inside this callback. Other
same-server calls from callbacks remain unsupported.

`wayembed_embed_attach()` writes `embed` only when it returns
`WAYEMBED_EMBED_STATUS_OK`.

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

The server issues `wayembed_embed *`. The host may store the pointer, but it
does not own it. The handle is valid until `on_embed_destroyed` returns, or
until `wayembed_server_destroy()` starts.

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

`wayembed_server` is not thread-safe. Serialize every call that touches the
same server. `wayembed_server_dispatch()` may run on any host thread, and
callbacks run on that thread. A recursive dispatch call is ignored.

## Opening A Plugin Display

When the plugin asks for a Wayland UI, open a plugin-side display and pass the
adapter handoff through the plugin format glue. The handoff token is
wayembed-specific. Do not use upstream floating-window Wayland support as the
embedding contract.

```c
struct wl_display *plugin_display =
    wayembed_server_open_client_display(server);

if (!plugin_display) {
    return CLAP_WINDOW_API_FAILED;
}

wayembed_adapter_handoff handoff = {
    .size = sizeof(handoff),
};

if (!wayembed_adapter_handoff_init(&handoff,
                                   WAYEMBED_ADAPTER_FORMAT_CLAP,
                                   server,
                                   plugin_display)) {
    return CLAP_WINDOW_API_FAILED;
}

carla_experimental_wayland_window window = {
    .api = handoff.format_token,
    .display = handoff.display,
};

plugin_gui->set_parent(plugin, &window);
plugin_gui->show(plugin);
```

The plugin sees a normal `wl_display *`: bind globals, create a surface, attach
buffers, and commit. The plugin also has to understand the wayembed token. A
plugin that only asks for upstream floating Wayland support is outside this
embedded path.

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

## Carla And Element Notes

Carla and Element already own the plugin-format layer. wayembed should sit
under that layer, not replace it.

The Element CLAP spike is the first real-host proof. It stays opt-in and does
not replace Element's XEmbed path. The spike proves the adapter token, display
handoff, and CLAP callback order. Visible embedding has a second runtime gate,
`ELEMENT_WAYEMBED_CLAP_EMBED=1`. Stock JUCE 8.0.12 on Linux still exposes an
X11 native window instead of a Wayland `wl_surface`, so Element logs that as a
blocker. When Element is built against the `greenm01/JUCE` `wayland-juce8`
fork with JUCE's Wayland backend enabled, the peer exposes the parent
`wl_surface` and host Wayland globals that `wayembed_embed_attach()` needs.

For CLAP, the host opens a wayembed display before GUI creation, initializes a
`WAYEMBED_ADAPTER_FORMAT_CLAP` handoff, and passes
`WAYEMBED_ADAPTER_CLAP_EXPERIMENTAL_API` plus the display through its
experimental plugin glue. The host still calls the CLAP GUI callbacks. The
plugin still creates the `wl_surface`.

For LV2, the host advertises `WAYEMBED_ADAPTER_LV2_EXPERIMENTAL_URI` only to
UIs that opt in. The LV2 feature payload carries the wayembed display. The host
keeps ownership of the server, display, and embed handle.

For VST3, the host uses
`WAYEMBED_ADAPTER_VST3_PLATFORM_TYPE_WAYLAND_SURFACE_ID` for the VST3 3.8
Wayland surface path. The host owns VST3 SDK integration and exposes the
wayembed display through its Wayland host object. The plugin still creates the
child `wl_surface`.

The shared editor path stays the same for all three formats: `on_surface_created`
calls `wayembed_embed_attach()` with the host editor parent surface, resize
calls `wayembed_embed_resize()`, hide or destroy closes the plugin display or
client fd, and `on_client_closed` clears the host's per-editor state.

Do not synthesize a parent surface for an X11-only host window. An XWayland
window is not a Wayland subsurface parent. Keep the display handoff proof alive
and report the missing parent `wl_surface` unless the host toolkit exposes one.

## Embedded Surface Contract

Embedded mode is for a plain plugin `wl_surface`. wayembed turns that surface
into a subsurface of the host parent surface.

`wayembed_embed_attach()` immediately:

- creates the upstream `wl_subsurface`;
- assigns the child surface the subsurface role;
- positions it with `get_subsurface_offset`;
- creates one active `wayembed_embed *` for the client;
- queues `on_embed_mapped`.

Only one active embed per client is supported. A second
`wayembed_embed_attach()` call while an embed is active returns
`WAYEMBED_EMBED_STATUS_ALREADY_EMBEDDED`. The host may ignore surfaces it does
not want to embed; they remain delegated surfaces. If the plugin destroys the
embedded child surface, wayembed destroys the embed and fires
`on_embed_destroyed`. The same client may later create another surface and
attach a new embed.

Attach status codes tell the host what to do:

| Status | Host action |
| --- | --- |
| `WAYEMBED_EMBED_STATUS_OK` | Store the returned embed handle. |
| `WAYEMBED_EMBED_STATUS_INVALID_ARGUMENT` | Fix the host call site. |
| `WAYEMBED_EMBED_STATUS_CLIENT_CLOSING` | Stop work for this client. |
| `WAYEMBED_EMBED_STATUS_ALREADY_EMBEDDED` | Reuse or destroy the active embed first. |
| `WAYEMBED_EMBED_STATUS_UNKNOWN_SURFACE` | Ignore this surface or wait for the next one. |
| `WAYEMBED_EMBED_STATUS_SURFACE_HAS_ROLE` | The plugin made the surface a toplevel, popup, cursor, or subsurface first. |
| `WAYEMBED_EMBED_STATUS_UNSUPPORTED` | The host did not provide `get_subcompositor()`, so embedded subsurface mode cannot start. |
| `WAYEMBED_EMBED_STATUS_UPSTREAM_FAILED` | Log diagnostics and fail the plugin UI. |
| `WAYEMBED_EMBED_STATUS_UNKNOWN_EMBED` | Drop the stale embed handle. |

Other C ABI helpers use `NULL`, `false`, or `-1` for simple failures such as
invalid arguments or allocation failure. Operations with recovery choices use
status codes.

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
size in the embed record and reapplies the current subsurface offset. If resize
fails and the host cannot recover, log the status and fail or hide the editor
area.

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
