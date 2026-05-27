#include "wayembed.h"
#include "wayembed_adapters.h"

#include <stddef.h>
#include <stdint.h>
#include <wayland-client.h>

static int connected_count = 0;
static int closed_count = 0;
static int mapped_count = 0;
static int resized_count = 0;
static int destroyed_count = 0;
static wayembed_client *last_client = NULL;

static int snapshot_clients(wayembed_snapshot *snapshot, size_t *clients)
{
    wayembed_snapshot_counts counts;
    counts.size = sizeof(counts);
    counts.version = WAYEMBED_ABI_VERSION;
    counts.clients = 0;
    counts.resources = 0;
    counts.surfaces = 0;
    counts.buffers = 0;
    counts.embeds = 0;
    counts.outputs = 0;
    if (!wayembed_snapshot_get_counts(snapshot, &counts)) {
        return 0;
    }
    *clients = counts.clients;
    return 1;
}

static void on_client_connected(void *userdata, wayembed_client *client)
{
    (void)userdata;
    if (client != NULL) {
        connected_count += 1;
        last_client = client;
    }
}

static void on_client_closed(void *userdata, wayembed_client *client)
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
    if (wayembed_abi_version() != WAYEMBED_ABI_VERSION) {
        return 1;
    }
    if (wayembed_adapter_abi_version() != WAYEMBED_ADAPTER_ABI_VERSION) {
        return 2;
    }

    if (wayembed_server_snapshot(NULL) != NULL) {
        return 3;
    }
    if (wayembed_snapshot_get_counts(NULL, NULL)) {
        return 4;
    }
    wayembed_snapshot_free(NULL);

    wayembed_host_interface host;
    host.size = sizeof(host);
    host.version = WAYEMBED_ABI_VERSION;
    host.userdata = NULL;
    host.get_compositor = NULL;
    host.get_subcompositor = NULL;
    host.get_shm = NULL;
    host.get_seat = NULL;
    host.get_xdg_wm_base = NULL;
    host.get_dmabuf = NULL;
    host.get_seat_capabilities = NULL;
    host.get_seat_name = NULL;
    host.get_output_info = NULL;
    host.get_subsurface_offset = NULL;
    host.on_client_connected = on_client_connected;
    host.on_surface_created = NULL;
    host.on_client_closed = on_client_closed;
    host.on_protocol_error = NULL;
    host.on_embed_mapped = on_embed_mapped;
    host.on_embed_resized = on_embed_resized;
    host.on_embed_destroyed = on_embed_destroyed;

    wayembed_server *server = wayembed_server_create(&host, NULL);
    if (server == NULL) {
        return 5;
    }

    if (wayembed_server_get_fd(server) < 0) {
        wayembed_server_destroy(server);
        return 6;
    }

    wayembed_snapshot *empty_snapshot = wayembed_server_snapshot(server);
    if (empty_snapshot == NULL) {
        wayembed_server_destroy(server);
        return 7;
    }
    size_t empty_clients = 99;
    if (!snapshot_clients(empty_snapshot, &empty_clients) || empty_clients != 0) {
        wayembed_snapshot_free(empty_snapshot);
        wayembed_server_destroy(server);
        return 8;
    }
    wayembed_snapshot_counts invalid_counts;
    invalid_counts.size = offsetof(wayembed_snapshot_counts, outputs);
    invalid_counts.version = WAYEMBED_ABI_VERSION;
    if (wayembed_snapshot_get_counts(empty_snapshot, &invalid_counts)) {
        wayembed_snapshot_free(empty_snapshot);
        wayembed_server_destroy(server);
        return 9;
    }
    invalid_counts.size = sizeof(invalid_counts);
    invalid_counts.version = WAYEMBED_ABI_VERSION + 1u;
    if (wayembed_snapshot_get_counts(empty_snapshot, &invalid_counts)) {
        wayembed_snapshot_free(empty_snapshot);
        wayembed_server_destroy(server);
        return 10;
    }
    wayembed_snapshot_free(empty_snapshot);

    /* open/close cycle. */
    struct wl_display *display = wayembed_server_open_client_display(server);
    if (display == NULL) {
        wayembed_server_destroy(server);
        return 11;
    }
    if (wl_display_get_fd(display) < 0) {
        wayembed_server_destroy(server);
        return 12;
    }
    wayembed_server_dispatch(server);
    if (connected_count != 1 || last_client == NULL) {
        wayembed_server_destroy(server);
        return 13;
    }

    wayembed_adapter_handoff handoff;
    handoff.size = sizeof(handoff);
    handoff.version = 0;
    handoff.format = WAYEMBED_ADAPTER_FORMAT_UNKNOWN;
    handoff.server = NULL;
    handoff.display = NULL;
    handoff.format_token = NULL;
    handoff.format_userdata = NULL;
    if (wayembed_adapter_handoff_validate(NULL)) {
        wayembed_server_destroy(server);
        return 14;
    }
    if (!wayembed_adapter_handoff_init(&handoff,
                                      WAYEMBED_ADAPTER_FORMAT_CLAP,
                                      server,
                                      display)) {
        wayembed_server_destroy(server);
        return 15;
    }
    if (!wayembed_adapter_handoff_validate(&handoff) ||
        handoff.version != WAYEMBED_ADAPTER_ABI_VERSION ||
        handoff.format != WAYEMBED_ADAPTER_FORMAT_CLAP ||
        handoff.display != display ||
        handoff.format_token == NULL) {
        wayembed_server_destroy(server);
        return 16;
    }
    handoff.version = WAYEMBED_ADAPTER_ABI_VERSION + 1u;
    if (wayembed_adapter_handoff_validate(&handoff)) {
        wayembed_server_destroy(server);
        return 17;
    }
    if (wayembed_adapter_handoff_init(&handoff,
                                     WAYEMBED_ADAPTER_FORMAT_UNKNOWN,
                                     server,
                                     display)) {
        wayembed_server_destroy(server);
        return 18;
    }

    wayembed_adapter_resize resize;
    resize.size = sizeof(resize);
    resize.version = WAYEMBED_ADAPTER_ABI_VERSION;
    resize.width = 640;
    resize.height = 480;
    resize.scale = 1.0;
    if (!wayembed_adapter_resize_validate(&resize)) {
        wayembed_server_destroy(server);
        return 19;
    }
    resize.width = -1;
    if (wayembed_adapter_resize_validate(&resize)) {
        wayembed_server_destroy(server);
        return 20;
    }

    wayembed_snapshot *open_snapshot = wayembed_server_snapshot(server);
    if (open_snapshot == NULL) {
        wayembed_server_destroy(server);
        return 21;
    }
    size_t open_clients = 0;
    if (!snapshot_clients(open_snapshot, &open_clients) || open_clients != 1) {
        wayembed_snapshot_free(open_snapshot);
        wayembed_server_destroy(server);
        return 22;
    }
    if (!wayembed_server_close_client_display(server, display)) {
        wayembed_snapshot_free(open_snapshot);
        wayembed_server_destroy(server);
        return 23;
    }
    wayembed_server_dispatch(server);
    if (closed_count != 1) {
        wayembed_snapshot_free(open_snapshot);
        wayembed_server_destroy(server);
        return 24;
    }
    if (mapped_count != 0 || resized_count != 0 || destroyed_count != 0) {
        wayembed_snapshot_free(open_snapshot);
        wayembed_server_destroy(server);
        return 25;
    }

    size_t still_open_clients = 0;
    if (!snapshot_clients(open_snapshot, &still_open_clients) ||
        still_open_clients != 1) {
        wayembed_snapshot_free(open_snapshot);
        wayembed_server_destroy(server);
        return 26;
    }
    wayembed_snapshot_free(open_snapshot);

    wayembed_snapshot *closed_snapshot = wayembed_server_snapshot(server);
    if (closed_snapshot == NULL) {
        wayembed_server_destroy(server);
        return 27;
    }
    size_t closed_clients = 99;
    if (!snapshot_clients(closed_snapshot, &closed_clients) ||
        closed_clients != 0) {
        wayembed_snapshot_free(closed_snapshot);
        wayembed_server_destroy(server);
        return 28;
    }
    wayembed_snapshot_free(closed_snapshot);

    /* Embed operations accept null client opaquely. */
    (void)wayembed_embed_attach(NULL, NULL, NULL);
    (void)wayembed_embed_resize(NULL, 0, 0);

    wayembed_server_destroy(server);
    return 0;
}
