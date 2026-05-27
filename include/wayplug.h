#ifndef WAYPLUG_H
#define WAYPLUG_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WAYPLUG_ABI_VERSION 1u

struct wl_compositor;
struct wl_display;
struct wl_event_queue;
struct wl_proxy;
struct wl_seat;
struct wl_shm;
struct wl_subcompositor;
struct wl_surface;
struct xdg_wm_base;
struct zwp_linux_dmabuf_v1;

typedef struct wayplug_server wayplug_server;
typedef struct wayplug_client wayplug_client;
typedef struct wayplug_snapshot wayplug_snapshot;

typedef struct wayplug_snapshot_counts {
    uint32_t size;
    uint32_t version;
    size_t clients;
    size_t resources;
    size_t surfaces;
    size_t buffers;
    size_t embeds;
    size_t outputs;
} wayplug_snapshot_counts;

typedef struct wayplug_host_interface {
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

    void (*on_client_connected)(void *userdata, wayplug_client *client);
    void (*on_surface_created)(void *userdata,
                               wayplug_client *client,
                               struct wl_surface *plugin_child_surface);
    void (*on_client_closed)(void *userdata, wayplug_client *client);
    void (*on_protocol_error)(void *userdata,
                              wayplug_client *client,
                              uint32_t code);
} wayplug_host_interface;

uint32_t wayplug_abi_version(void);

wayplug_server *wayplug_server_create(const wayplug_host_interface *host,
                                      struct wl_event_queue *queue);

void wayplug_server_destroy(wayplug_server *server);

int wayplug_server_get_fd(wayplug_server *server);
void wayplug_server_dispatch(wayplug_server *server);
void wayplug_server_flush(wayplug_server *server);

wayplug_snapshot *wayplug_server_snapshot(wayplug_server *server);
bool wayplug_snapshot_get_counts(const wayplug_snapshot *snapshot,
                                 wayplug_snapshot_counts *counts);
void wayplug_snapshot_free(wayplug_snapshot *snapshot);

struct wl_display *wayplug_server_open_client_display(wayplug_server *server);
bool wayplug_server_close_client_display(wayplug_server *server,
                                         struct wl_display *display);

struct wl_proxy *wayplug_server_create_proxy(wayplug_server *server,
                                             struct wl_display *client_display,
                                             struct wl_proxy *host_object);

void wayplug_server_destroy_proxy(wayplug_server *server,
                                  struct wl_proxy *proxy);

bool wayplug_embed_attach(wayplug_client *client,
                          struct wl_surface *parent_surface,
                          struct wl_surface *child_surface);

bool wayplug_embed_resize(wayplug_client *client,
                          int32_t width,
                          int32_t height);

#ifdef __cplusplus
}
#endif

#endif
