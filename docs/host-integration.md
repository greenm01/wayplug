# Host Integration Walkthrough

This document walks a host application through every wayplug call it needs
to embed a Wayland-native plugin editor. The host in the examples is
Carla-shaped: a Qt-based audio plugin host with its own Wayland connection
and an editor area inside a host window.

The walkthrough is the validation harness for the [C ABI
Sketch](c-abi-sketch.md). Anything awkward to write below is an ABI mistake
that should be fixed before code lands.

## Shape of a Session

```text
host                                wayplug                       plugin
  | wayplug_server_create()           |                              |
  |---------------------------------->|                              |
  | wayplug_server_get_fd()           |                              |
  |---------------------------------->|                              |
  | adds fd to host event loop        |                              |
  |                                   |                              |
  | wayplug_server_open_client_display|                              |
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
  | wayplug_embed_resize(...)         |                              |
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
  | wayplug_server_destroy()          |                              |
  |---------------------------------->|                              |
```

## Setting Up the Host Interface

The host provides upstream globals (compositor, shm, seat) and lifecycle
callbacks through a single `wayplug_host_interface` struct. The current
[C ABI Sketch](c-abi-sketch.md) shows the getters; the walkthrough adds
the lifecycle half so this can be exercised end-to-end.

```c
#include <wayplug.h>

struct carla_host {
    struct wl_display *upstream_display;
    struct wl_compositor *upstream_compositor;
    struct wl_subcompositor *upstream_subcompositor;
    struct wl_shm *upstream_shm;
    struct wl_seat *upstream_seat;

    struct wl_surface *editor_parent_surface;
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

static void on_client_connected(void *u, wayplug_client *client) {
    (void)u; (void)client;
    /* Optional logging. */
}

static void on_surface_created(void *u, wayplug_client *client,
                               struct wl_surface *plugin_child_surface) {
    struct carla_host *h = u;
    /* Wrap the child surface as a subsurface of the editor parent. */
    wayplug_embed_attach(client,
                         h->editor_parent_surface,
                         plugin_child_surface);
}

static void on_client_closed(void *u, wayplug_client *client) {
    (void)client;
    struct carla_host *h = u;
    carla_clear_editor_area(h);
}
```

The struct definition Carla fills in:

```c
static struct carla_host host_state = { /* initialized at startup */ };

static const wayplug_host_interface host_iface = {
    .size = sizeof(wayplug_host_interface),
    .version = WAYPLUG_ABI_VERSION,
    .userdata = &host_state,

    .get_compositor = get_compositor,
    .get_subcompositor = get_subcompositor,
    .get_shm = get_shm,
    .get_seat = get_seat,
    .get_subsurface_offset = get_subsurface_offset,

    .on_client_connected = on_client_connected,
    .on_surface_created = on_surface_created,
    .on_client_closed = on_client_closed,
};
```

## Creating the Server

```c
wayplug_server *server = wayplug_server_create(&host_iface, /* queue */ NULL);
if (!server) {
    fprintf(stderr, "wayplug_server_create failed\n");
    return -1;
}
```

The server takes a const pointer to the host interface and copies what it
needs. The host owns the struct; wayplug must not retain function pointers
across a destroy. The `queue` argument is the upstream `wl_event_queue` the
server should drive — `NULL` means the default queue.

## Event Loop Integration

wayplug never spawns threads or owns a poll loop. The host adds the
server's fd to its existing event loop.

```c
int server_fd = wayplug_server_get_fd(server);

struct pollfd pfds[2] = {
    { .fd = upstream_fd,  .events = POLLIN },
    { .fd = server_fd,    .events = POLLIN },
};

while (running) {
    wayplug_server_flush(server);
    wl_display_flush(host_state.upstream_display);

    if (poll(pfds, 2, -1) < 0) break;

    if (pfds[0].revents & POLLIN)
        wl_display_dispatch(host_state.upstream_display);
    if (pfds[1].revents & POLLIN)
        wayplug_server_dispatch(server);
}
```

`wayplug_server_dispatch` fires lifecycle callbacks synchronously before
it returns. Inside a callback the host may issue calls on its *upstream*
connection, but must not call back into the same `wayplug_server` —
re-entrant calls are undefined.

## Opening a Client Connection for a Plugin

When Carla loads a plugin and the plugin requests `CLAP_WINDOW_API_WAYLAND`
or an LV2 Wayland UI:

```c
struct wl_display *plugin_display =
    wayplug_server_open_client_display(server);

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

When the plugin calls `wl_compositor.create_surface()`, wayplug forwards
the request, registers the new surface in its model, and invokes
`on_surface_created` on the host. The host parents the child surface as a
subsurface of its editor area:

```c
static void on_surface_created(void *u, wayplug_client *client,
                               struct wl_surface *plugin_child_surface) {
    struct carla_host *h = u;
    wayplug_embed_attach(client,
                         h->editor_parent_surface,
                         plugin_child_surface);
}
```

`wayplug_embed_attach` creates a `wl_subsurface`, positions it at the
offset returned by `get_subsurface_offset`, and tracks it in the model. The
host does not see `wl_subcompositor` directly — wayplug owns that wiring.

## Resize Round-Trip

When the user resizes Carla's window, Carla updates its editor dimensions
and notifies wayplug. wayplug stores the new size in the embed record and
sends the relevant subsurface positioning calls upstream. If the plugin
needs a size hint, wayplug fires the configured plugin-format extension
(CLAP `gui.set_size`, LV2 idle interface) on the host's behalf.

```c
void carla_on_window_resize(int new_width, int new_height) {
    host_state.editor_width = new_width;
    host_state.editor_height = new_height;

    wayplug_embed_resize(plugin_client, new_width, new_height);
}
```

## Plugin Disconnect

When the plugin's UI thread exits or the plugin closes its display,
wayplug:

1. Walks the client's owned objects in teardown order (see
   [Architecture § Teardown Order](architecture.md#teardown-order)).
2. Fires `on_client_closed` after the teardown completes.
3. Releases the client row.

The host clears its editor area and is ready to host the next plugin.

## Shutdown

```c
wayplug_server_destroy(server);
```

Destroy invalidates every handle the server issued, including
`plugin_display` values and any `wayplug_client *` the host retained. The
host must not call wayplug functions after destroy returns.

## What This Walkthrough Validates

Drafting the walkthrough exposed three things the C ABI sketch needs
before code lands:

1. **Lifecycle callback fields** on `wayplug_host_interface`
   (`on_client_connected`, `on_surface_created`, `on_client_closed`, at
   minimum). The current sketch only covers upstream getters.
2. **An `embed_attach` / `embed_resize` surface** so the host doesn't
   touch `wl_subcompositor` directly. Without these, the host has to
   reach past wayplug to position the child surface, which defeats the
   delegated-server pattern.
3. **A `wayplug_client *` opaque handle** the host can hold between the
   `open_client_display` call and a subsequent operation
   (`embed_resize`). Without it the host has to map `wl_display *` back
   to a client every time, duplicating the index wayplug already owns.

Folding these into `c-abi-sketch.md` is tracked separately.
