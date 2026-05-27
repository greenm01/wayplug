#include "wayplug.h"

#include <stddef.h>
#include <wayland-client.h>

static int connected_count = 0;
static int closed_count = 0;
static int mapped_count = 0;
static int resized_count = 0;
static int destroyed_count = 0;
static wayplug_client *last_client = NULL;

static int snapshot_clients(wayplug_snapshot *snapshot, size_t *clients)
{
    wayplug_snapshot_counts counts;
    counts.size = sizeof(counts);
    counts.version = WAYPLUG_ABI_VERSION;
    counts.clients = 0;
    counts.resources = 0;
    counts.surfaces = 0;
    counts.buffers = 0;
    counts.embeds = 0;
    counts.outputs = 0;
    if (!wayplug_snapshot_get_counts(snapshot, &counts)) {
        return 0;
    }
    *clients = counts.clients;
    return 1;
}

static void on_client_connected(void *userdata, wayplug_client *client)
{
    (void)userdata;
    if (client != NULL) {
        connected_count += 1;
        last_client = client;
    }
}

static void on_client_closed(void *userdata, wayplug_client *client)
{
    (void)userdata;
    if (client != NULL) {
        closed_count += 1;
    }
}

static void on_embed_mapped(void *userdata, uint32_t embed_id)
{
    (void)userdata;
    if (embed_id != 0) {
        mapped_count += 1;
    }
}

static void on_embed_resized(void *userdata,
                             uint32_t embed_id,
                             int32_t width,
                             int32_t height)
{
    (void)userdata;
    if (embed_id != 0 && width >= 0 && height >= 0) {
        resized_count += 1;
    }
}

static void on_embed_destroyed(void *userdata, uint32_t embed_id)
{
    (void)userdata;
    if (embed_id != 0) {
        destroyed_count += 1;
    }
}

int main(void)
{
    if (wayplug_abi_version() != WAYPLUG_ABI_VERSION) {
        return 1;
    }

    if (wayplug_server_snapshot(NULL) != NULL) {
        return 2;
    }
    if (wayplug_snapshot_get_counts(NULL, NULL)) {
        return 3;
    }
    wayplug_snapshot_free(NULL);

    wayplug_host_interface host;
    host.size = sizeof(host);
    host.version = WAYPLUG_ABI_VERSION;
    host.userdata = NULL;
    host.get_compositor = NULL;
    host.get_subcompositor = NULL;
    host.get_shm = NULL;
    host.get_seat = NULL;
    host.get_xdg_wm_base = NULL;
    host.get_dmabuf = NULL;
    host.get_seat_capabilities = NULL;
    host.get_seat_name = NULL;
    host.get_subsurface_offset = NULL;
    host.on_client_connected = on_client_connected;
    host.on_surface_created = NULL;
    host.on_client_closed = on_client_closed;
    host.on_protocol_error = NULL;
    host.on_embed_mapped = on_embed_mapped;
    host.on_embed_resized = on_embed_resized;
    host.on_embed_destroyed = on_embed_destroyed;

    wayplug_server *server = wayplug_server_create(&host, NULL);
    if (server == NULL) {
        return 4;
    }

    if (wayplug_server_get_fd(server) < 0) {
        wayplug_server_destroy(server);
        return 5;
    }

    wayplug_snapshot *empty_snapshot = wayplug_server_snapshot(server);
    if (empty_snapshot == NULL) {
        wayplug_server_destroy(server);
        return 6;
    }
    size_t empty_clients = 99;
    if (!snapshot_clients(empty_snapshot, &empty_clients) || empty_clients != 0) {
        wayplug_snapshot_free(empty_snapshot);
        wayplug_server_destroy(server);
        return 7;
    }
    wayplug_snapshot_counts invalid_counts;
    invalid_counts.size = offsetof(wayplug_snapshot_counts, outputs);
    invalid_counts.version = WAYPLUG_ABI_VERSION;
    if (wayplug_snapshot_get_counts(empty_snapshot, &invalid_counts)) {
        wayplug_snapshot_free(empty_snapshot);
        wayplug_server_destroy(server);
        return 8;
    }
    invalid_counts.size = sizeof(invalid_counts);
    invalid_counts.version = WAYPLUG_ABI_VERSION + 1u;
    if (wayplug_snapshot_get_counts(empty_snapshot, &invalid_counts)) {
        wayplug_snapshot_free(empty_snapshot);
        wayplug_server_destroy(server);
        return 9;
    }
    wayplug_snapshot_free(empty_snapshot);

    /* open/close cycle. */
    struct wl_display *display = wayplug_server_open_client_display(server);
    if (display == NULL) {
        wayplug_server_destroy(server);
        return 10;
    }
    if (wl_display_get_fd(display) < 0) {
        wayplug_server_destroy(server);
        return 11;
    }
    wayplug_server_dispatch(server);
    if (connected_count != 1 || last_client == NULL) {
        wayplug_server_destroy(server);
        return 12;
    }

    wayplug_snapshot *open_snapshot = wayplug_server_snapshot(server);
    if (open_snapshot == NULL) {
        wayplug_server_destroy(server);
        return 13;
    }
    size_t open_clients = 0;
    if (!snapshot_clients(open_snapshot, &open_clients) || open_clients != 1) {
        wayplug_snapshot_free(open_snapshot);
        wayplug_server_destroy(server);
        return 14;
    }
    if (!wayplug_server_close_client_display(server, display)) {
        wayplug_snapshot_free(open_snapshot);
        wayplug_server_destroy(server);
        return 15;
    }
    wayplug_server_dispatch(server);
    if (closed_count != 1) {
        wayplug_snapshot_free(open_snapshot);
        wayplug_server_destroy(server);
        return 16;
    }
    if (mapped_count != 0 || resized_count != 0 || destroyed_count != 0) {
        wayplug_snapshot_free(open_snapshot);
        wayplug_server_destroy(server);
        return 17;
    }

    size_t still_open_clients = 0;
    if (!snapshot_clients(open_snapshot, &still_open_clients) ||
        still_open_clients != 1) {
        wayplug_snapshot_free(open_snapshot);
        wayplug_server_destroy(server);
        return 18;
    }
    wayplug_snapshot_free(open_snapshot);

    wayplug_snapshot *closed_snapshot = wayplug_server_snapshot(server);
    if (closed_snapshot == NULL) {
        wayplug_server_destroy(server);
        return 19;
    }
    size_t closed_clients = 99;
    if (!snapshot_clients(closed_snapshot, &closed_clients) ||
        closed_clients != 0) {
        wayplug_snapshot_free(closed_snapshot);
        wayplug_server_destroy(server);
        return 20;
    }
    wayplug_snapshot_free(closed_snapshot);

    /* Embed operations accept null client opaquely. */
    (void)wayplug_embed_attach(NULL, NULL, NULL);
    (void)wayplug_embed_resize(NULL, 0, 0);

    wayplug_server_destroy(server);
    return 0;
}
