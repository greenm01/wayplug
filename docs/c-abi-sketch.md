# C ABI Sketch

This is historical design context, not the committed API. The source of
truth for the public ABI is [../include/wayembed.h](../include/wayembed.h).
The sketch below remains useful for seeing the intended C shape and ABI
rules that guided the first implementation.

```c
#pragma once

#include <stdbool.h>
#include <stdint.h>

struct wl_compositor;
struct wl_display;
struct wl_event_queue;
struct wl_proxy;
struct wl_seat;
struct wl_shm;
struct wl_subcompositor;
struct wl_surface;
struct wl_output;
struct xdg_wm_base;
struct zwp_linux_dmabuf_v1;

typedef struct wayembed_server wayembed_server;
typedef struct wayembed_client wayembed_client;
typedef struct wayembed_resource wayembed_resource;

typedef struct wayembed_output_info {
    uint32_t size;
    uint32_t version;
    int32_t x;
    int32_t y;
    int32_t physical_width;
    int32_t physical_height;
    int32_t subpixel;
    const char *make;
    const char *model;
    int32_t transform;
    uint32_t mode_flags;
    int32_t mode_width;
    int32_t mode_height;
    int32_t mode_refresh;
    int32_t scale;
    const char *name;
    const char *description;
} wayembed_output_info;

typedef struct wayembed_host_interface {
    uint32_t size;
    uint32_t version;
    void *userdata;

    struct wl_compositor *(*get_compositor)(void *userdata);
    struct wl_subcompositor *(*get_subcompositor)(void *userdata);
    struct wl_shm *(*get_shm)(void *userdata);
    struct wl_seat *(*get_seat)(void *userdata);
    struct xdg_wm_base *(*get_xdg_wm_base)(void *userdata);
    struct zwp_linux_dmabuf_v1 *(*get_dmabuf)(void *userdata);

    bool (*get_subsurface_offset)(void *userdata,
                                  int32_t *x,
                                  int32_t *y,
                                  struct wl_display *display,
                                  struct wl_surface *parent,
                                  struct wl_surface *child);

    void (*on_client_connected)(void *userdata, wayembed_client *client);
    void (*on_surface_created)(void *userdata,
                               wayembed_client *client,
                               struct wl_surface *plugin_child_surface);
    void (*on_client_closed)(void *userdata, wayembed_client *client);
    void (*on_protocol_error)(void *userdata,
                              wayembed_client *client,
                              uint32_t code);
    void (*on_embed_mapped)(void *userdata, uint32_t embed_id);
    void (*on_embed_resized)(void *userdata,
                             uint32_t embed_id,
                             int32_t width,
                             int32_t height);
    void (*on_embed_destroyed)(void *userdata, uint32_t embed_id);

    uint32_t (*get_seat_capabilities)(void *userdata);
    const char *(*get_seat_name)(void *userdata);
    bool (*get_output_info)(void *userdata, wayembed_output_info *info);
} wayembed_host_interface;

wayembed_server *wayembed_server_create(const wayembed_host_interface *host,
                                      struct wl_event_queue *queue);

void wayembed_server_destroy(wayembed_server *server);

int wayembed_server_get_fd(wayembed_server *server);
void wayembed_server_dispatch(wayembed_server *server);
void wayembed_server_flush(wayembed_server *server);

struct wl_display *wayembed_server_open_client_display(wayembed_server *server);
bool wayembed_server_close_client_display(wayembed_server *server,
                                         struct wl_display *display);

struct wl_proxy *wayembed_server_create_proxy(wayembed_server *server,
                                             struct wl_display *client_display,
                                             struct wl_proxy *host_object,
                                             wayembed_resource *implementation);
void wayembed_server_destroy_proxy(wayembed_server *server,
                                  struct wl_proxy *proxy);
```

## ABI Rules

- All public structs should contain `size` and `version` fields.
- Append-only callback-table fields are guarded by `size`; missing fields
  are treated as null callbacks.
- Public object types should be opaque.
- The library owns objects returned by `wayembed_*_create`.
- Callers release objects with matching destroy/close functions.
- The API should not expose implementation-language types.
- Avoid callbacks from arbitrary threads unless explicitly documented.
