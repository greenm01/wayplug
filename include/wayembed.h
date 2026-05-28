#ifndef WAYEMBED_H
#define WAYEMBED_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WAYEMBED_ABI_VERSION 2u

#define WAYEMBED_FEATURE_COMPOSITOR (1ull << 0)
#define WAYEMBED_FEATURE_SUBCOMPOSITOR (1ull << 1)
#define WAYEMBED_FEATURE_SURFACE (1ull << 2)
#define WAYEMBED_FEATURE_SHM_BUFFER (1ull << 3)
#define WAYEMBED_FEATURE_EMBED_SESSION (1ull << 4)
#define WAYEMBED_FEATURE_SEAT (1ull << 5)
#define WAYEMBED_FEATURE_POINTER (1ull << 6)
#define WAYEMBED_FEATURE_KEYBOARD (1ull << 7)
#define WAYEMBED_FEATURE_TOUCH (1ull << 8)
#define WAYEMBED_FEATURE_OUTPUT (1ull << 9)
#define WAYEMBED_FEATURE_XDG_SHELL (1ull << 10)
#define WAYEMBED_FEATURE_CLIENT_FD (1ull << 11)
#define WAYEMBED_FEATURE_LINUX_DMABUF (1ull << 12)

#define WAYEMBED_EMBED_STATUS_OK 0u
#define WAYEMBED_EMBED_STATUS_INVALID_ARGUMENT 1u
#define WAYEMBED_EMBED_STATUS_CLIENT_CLOSING 2u
#define WAYEMBED_EMBED_STATUS_ALREADY_EMBEDDED 3u
#define WAYEMBED_EMBED_STATUS_UNKNOWN_SURFACE 4u
#define WAYEMBED_EMBED_STATUS_SURFACE_HAS_ROLE 5u
#define WAYEMBED_EMBED_STATUS_UNSUPPORTED 6u
#define WAYEMBED_EMBED_STATUS_UPSTREAM_FAILED 7u
#define WAYEMBED_EMBED_STATUS_UNKNOWN_EMBED 8u

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
typedef struct wayembed_embed wayembed_embed;
typedef struct wayembed_snapshot wayembed_snapshot;

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

typedef struct wayembed_snapshot_counts {
    uint32_t size;
    uint32_t version;
    size_t clients;
    size_t resources;
    size_t surfaces;
    size_t buffers;
    size_t embeds;
    size_t outputs;
} wayembed_snapshot_counts;

typedef struct wayembed_features {
    uint32_t size;
    uint32_t version;
    uint64_t flags;
} wayembed_features;

typedef struct wayembed_embed_attach_info {
    uint32_t size;
    uint32_t version;
    wayembed_client *client;
    struct wl_surface *parent_surface;
    struct wl_surface *child_surface;
} wayembed_embed_attach_info;

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

    /* display is NULL for fd-opened clients. */
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
    void (*on_embed_mapped)(void *userdata, wayembed_embed *embed);
    void (*on_embed_resized)(void *userdata,
                             wayembed_embed *embed,
                             int32_t width,
                             int32_t height);
    void (*on_embed_destroyed)(void *userdata, wayembed_embed *embed);

    uint32_t (*get_seat_capabilities)(void *userdata);
    const char *(*get_seat_name)(void *userdata);
    bool (*get_output_info)(void *userdata, wayembed_output_info *info);
} wayembed_host_interface;

uint32_t wayembed_abi_version(void);

/* Reports the protocol features compiled into this build. */
bool wayembed_get_features(wayembed_features *features);

/* Creates a server. The caller owns the returned handle. */
wayembed_server *wayembed_server_create(const wayembed_host_interface *host,
                                        struct wl_event_queue *queue);

/* Destroys the server and invalidates every handle it issued. */
void wayembed_server_destroy(wayembed_server *server);

int wayembed_server_get_fd(wayembed_server *server);

/* Dispatches pending server work. Calls for one server must be serialized.
 * Host callbacks run on the thread that calls this function. */
void wayembed_server_dispatch(wayembed_server *server);
void wayembed_server_flush(wayembed_server *server);

/* Returns a caller-owned snapshot. Free it with wayembed_snapshot_free(). */
wayembed_snapshot *wayembed_server_snapshot(wayembed_server *server);
bool wayembed_snapshot_get_counts(const wayembed_snapshot *snapshot,
                                  wayembed_snapshot_counts *counts);
void wayembed_snapshot_free(wayembed_snapshot *snapshot);

/* Opens a plugin-side display.
 * Close it with wayembed_server_close_client_display(). */
struct wl_display *wayembed_server_open_client_display(wayembed_server *server);
bool wayembed_server_close_client_display(wayembed_server *server,
                                          struct wl_display *display);

/* Opens a plugin-side connection fd for out-of-process handoff.
 * The caller owns the returned fd. Close the client with
 * wayembed_server_close_client(), or close the fd and dispatch the server. */
int wayembed_server_open_client_fd(wayembed_server *server,
                                   wayembed_client **out_client);
bool wayembed_server_close_client(wayembed_server *server,
                                  wayembed_client *client);

struct wl_proxy *wayembed_server_create_proxy(wayembed_server *server,
                                              struct wl_display *client_display,
                                              struct wl_proxy *host_object);

void wayembed_server_destroy_proxy(wayembed_server *server,
                                   struct wl_proxy *proxy);

/* Attaches a plugin child surface to a host parent surface.
 * May be called synchronously from on_surface_created. */
uint32_t wayembed_embed_attach(const wayembed_embed_attach_info *info,
                               wayembed_embed **out_embed);

uint32_t wayembed_embed_resize(wayembed_embed *embed,
                               int32_t width,
                               int32_t height);
uint32_t wayembed_embed_id(const wayembed_embed *embed);
wayembed_client *wayembed_embed_client(const wayembed_embed *embed);

#ifdef __cplusplus
}
#endif

#endif
