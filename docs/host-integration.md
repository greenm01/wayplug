# Host Integration Walkthrough

This document walks a host application through every wayembed call it needs
to embed a Wayland-native plugin editor. The host in the examples is
Carla-shaped: a Qt-based audio plugin host with its own Wayland connection
and an editor area inside a host window.

The public ABI in [../include/wayembed.h](../include/wayembed.h) is the source
of truth. This walkthrough is the validation harness for that ABI: anything
awkward to write below is an ABI mistake that should be fixed before code
lands.

## Shape of a Session

```text
host                                wayembed                       plugin
  | wayembed_server_create()           |                              |
  |---------------------------------->|                              |
  | wayembed_server_get_fd()           |                              |
  |---------------------------------->|                              |
  | adds fd to host event loop        |                              |
  |                                   |                              |
  | wayembed_server_open_client_display|                              |
  |---------------------------------->|                              |
  |          wl_display * (plugin side)                              |
  |<----------------------------------|                              |
  | hands display to plugin via       |                              |
  | CLAP_WINDOW_API_WAYLAND / LV2 UI  |                              |
  |                                   |                              |
  |                                   |     wl_compositor.bind       |
  |                                   |<-----------------------------|
  |                                   |     wl_surface.create        |
  |                                   |<-----------------------------|
  | on_surface_created (callback)     |                              |
  |<----------------------------------|                              |
  | parents subsurface in editor area |                              |
  |                                   |                              |
  | wayembed_embed_resize(...)         |                              |
  |---------------------------------->|                              |
  |                                   |     wl_subsurface.set_pos    |
  |                                   |----------------------------->|
  |                                   |                              |
  | plugin disconnects                |                              |
  |                                   |<-----------------------------|
  | on_client_closed (callback)       |                              |
  |<----------------------------------|                              |
  | clears editor area                |                              |
  |                                   |                              |
  | wayembed_server_destroy()          |                              |
  |---------------------------------->|                              |
```

## Setting Up the Host Interface

The host provides upstream globals (compositor, shm, seat) and lifecycle
callbacks through a single `wayembed_host_interface` struct. Null function
pointers disable optional globals or notifications.

```c
#include <wayembed.h>

struct carla_host {
    struct wl_display *upstream_display;
    struct wl_compositor *upstream_compositor;
    struct wl_subcompositor *upstream_subcompositor;
    struct wl_shm *upstream_shm;
    struct wl_seat *upstream_seat;
    struct xdg_wm_base *upstream_xdg_wm_base;

    struct wl_surface *editor_parent_surface;
    int editor_x_in_window;
    int editor_y_in_window;
    int editor_width;
    int editor_height;
};

static struct wl_compositor *get_compositor(void *u) {
    return ((struct carla_host *)u)->upstream_compositor;
}

static struct wl_subcompositor *get_subcompositor(void *u) {
    return ((struct carla_host *)u)->upstream_subcompositor;
}

static struct wl_shm *get_shm(void *u) {
    return ((struct carla_host *)u)->upstream_shm;
}

static struct wl_seat *get_seat(void *u) {
    return ((struct carla_host *)u)->upstream_seat;
}

static struct xdg_wm_base *get_xdg_wm_base(void *u) {
    return ((struct carla_host *)u)->upstream_xdg_wm_base;
}

static uint32_t get_seat_capabilities(void *u) {
    (void)u;
    return WL_SEAT_CAPABILITY_POINTER | WL_SEAT_CAPABILITY_KEYBOARD;
}

static const char *get_seat_name(void *u) {
    (void)u;
    return "carla-seat";
}

static bool get_output_info(void *u, wayembed_output_info *info) {
    (void)u;
    info->mode_width = 1920;
    info->mode_height = 1080;
    info->scale = 1;
    info->name = "wayembed-host-output";
    return true;
}

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

static void on_client_connected(void *u, wayembed_client *client) {
    (void)u; (void)client;
    /* Optional logging. */
}

static void on_protocol_error(void *u, wayembed_client *client, uint32_t code) {
    (void)u; (void)client; (void)code;
    /* Optional diagnostics. */
}

static void on_surface_created(void *u, wayembed_client *client,
                               struct wl_surface *plugin_child_surface) {
    struct carla_host *h = u;
    /* Wrap the child surface as a subsurface of the editor parent. */
    wayembed_embed_attach(client,
                         h->editor_parent_surface,
                         plugin_child_surface);
}

static void on_client_closed(void *u, wayembed_client *client) {
    (void)client;
    struct carla_host *h = u;
    carla_clear_editor_area(h);
}

static void on_embed_mapped(void *u, uint32_t embed_id) {
    (void)u; (void)embed_id;
    /* Optional logging. */
}

static void on_embed_resized(void *u, uint32_t embed_id,
                             int32_t width, int32_t height) {
    (void)u; (void)embed_id; (void)width; (void)height;
    /* Optional logging. */
}

static void on_embed_destroyed(void *u, uint32_t embed_id) {
    (void)u; (void)embed_id;
    /* Optional cleanup/logging. */
}
```

The struct definition Carla fills in:

```c
static struct carla_host host_state = { /* initialized at startup */ };

static const wayembed_host_interface host_iface = {
    .size = sizeof(wayembed_host_interface),
    .version = WAYEMBED_ABI_VERSION,
    .userdata = &host_state,

    .get_compositor = get_compositor,
    .get_subcompositor = get_subcompositor,
    .get_shm = get_shm,
    .get_seat = get_seat,
    .get_xdg_wm_base = get_xdg_wm_base,
    .get_dmabuf = NULL,
    .get_subsurface_offset = get_subsurface_offset,

    .get_seat_capabilities = get_seat_capabilities,
    .get_seat_name = get_seat_name,
    .get_output_info = get_output_info,

    .on_client_connected = on_client_connected,
    .on_surface_created = on_surface_created,
    .on_client_closed = on_client_closed,
    .on_protocol_error = on_protocol_error,
    .on_embed_mapped = on_embed_mapped,
    .on_embed_resized = on_embed_resized,
    .on_embed_destroyed = on_embed_destroyed,
};
```

## Creating the Server

```c
wayembed_server *server = wayembed_server_create(&host_iface, /* queue */ NULL);
if (!server) {
    fprintf(stderr, "wayembed_server_create failed\n");
    return -1;
}
```

The server takes a const pointer to the host interface and copies what it
needs. The host owns the struct; wayembed must not retain function pointers
across a destroy. The `queue` argument is the upstream `wl_event_queue` the
server should drive — `NULL` means the default queue.

## Event Loop Integration

wayembed never spawns threads or owns a poll loop. The host adds the
server's fd to its existing event loop.

```c
int server_fd = wayembed_server_get_fd(server);

struct pollfd pfds[2] = {
    { .fd = upstream_fd,  .events = POLLIN },
    { .fd = server_fd,    .events = POLLIN },
};

while (running) {
    wayembed_server_flush(server);
    wl_display_flush(host_state.upstream_display);

    if (poll(pfds, 2, -1) < 0) break;

    if (pfds[0].revents & POLLIN)
        wl_display_dispatch(host_state.upstream_display);
    if (pfds[1].revents & POLLIN)
        wayembed_server_dispatch(server);
}
```

`wayembed_server_dispatch` fires lifecycle callbacks synchronously before
it returns. Inside a callback the host may issue calls on its *upstream*
connection. The one supported same-server call is
`wayembed_embed_attach` from `on_surface_created`, which creates the
embedded editor session for that plugin client. Other same-server calls
from lifecycle callbacks are undefined.

## Opening a Client Connection for a Plugin

When Carla loads a plugin and the plugin requests `CLAP_WINDOW_API_WAYLAND`
or an LV2 Wayland UI:

```c
struct wl_display *plugin_display =
    wayembed_server_open_client_display(server);

if (!plugin_display) {
    return CLAP_WINDOW_API_FAILED;
}

/* Hand to the plugin per its format. */
clap_window_t window = {
    .api = CLAP_WINDOW_API_WAYLAND,
    .wayland = plugin_display,
};
plugin_gui->set_parent(plugin, &window);
plugin_gui->show(plugin);
```

The plugin sees `plugin_display` as its `wl_display *` and proceeds with
standard Wayland client code: bind `wl_compositor`, create `wl_surface`,
attach buffers, commit.

## Receiving the Plugin's Surface

When the plugin calls `wl_compositor.create_surface()`, wayembed forwards
the request, registers the new surface in its model, and invokes
`on_surface_created` on the host. The host parents the child surface as a
subsurface of its editor area:

```c
static void on_surface_created(void *u, wayembed_client *client,
                               struct wl_surface *plugin_child_surface) {
    struct carla_host *h = u;
    wayembed_embed_attach(client,
                         h->editor_parent_surface,
                         plugin_child_surface);
}
```

`wayembed_embed_attach` creates a `wl_subsurface`, positions it at the
offset returned by `get_subsurface_offset`, and tracks it in the model. The
host does not see `wl_subcompositor` directly — wayembed owns that wiring.
One client can have one active embedded editor session. If attach returns
`false`, no session was established and the host should not call
`wayembed_embed_resize` for that client until another surface is created and
attached.

## Resize Round-Trip

When the user resizes Carla's window, Carla updates its editor dimensions
and notifies wayembed. wayembed stores the new size in the embed record and
sends the relevant subsurface positioning calls upstream. Width and height
must be non-negative; zero is accepted. `wayembed_embed_resize` returns
`false` if the client is closing or has no active embedded session.

If the plugin needs a size hint, a plugin-format adapter can layer that on
top of this resize notification path. The core library stays
format-neutral.

```c
void carla_on_window_resize(int new_width, int new_height) {
    host_state.editor_width = new_width;
    host_state.editor_height = new_height;

    wayembed_embed_resize(plugin_client, new_width, new_height);
}
```

## Plugin Disconnect

When the plugin's UI thread exits or the plugin closes its display,
wayembed:

1. Walks the client's owned objects in teardown order (see
   [Architecture § Teardown Order](architecture.md#teardown-order)).
2. Releases wayembed-owned embed wiring, including the internal
   `wl_subsurface` proxy.
3. Fires `on_embed_destroyed` for active embedded sessions.
4. Fires `on_client_closed` after embed teardown completes.
5. Releases the client row.

The host clears its editor area and is ready to host the next plugin.

## Shutdown

```c
wayembed_server_destroy(server);
```

Destroy invalidates every handle the server issued, including
`plugin_display` values and any `wayembed_client *` the host retained. The
host must not call wayembed functions after destroy returns.

## Embedded Session Contract

The public ABI stays client-scoped. Internally, wayembed treats a successful
`wayembed_embed_attach` as the start of one embedded editor session for that
client. `wayembed_embed_resize` targets that active session, and client
disconnect or server destroy ends it. A future plugin-format adapter may wrap
this in a higher-level handle if real host integrations need one.
