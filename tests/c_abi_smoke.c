#include "wayembed.h"
#include "wayembed_adapters.h"

#include <stddef.h>
#include <stdint.h>
#include <math.h>
#include <string.h>
#include <unistd.h>
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

static int check_feature_flags(uint64_t flags)
{
    const uint64_t expected =
        WAYEMBED_FEATURE_COMPOSITOR |
        WAYEMBED_FEATURE_SUBCOMPOSITOR |
        WAYEMBED_FEATURE_SURFACE |
        WAYEMBED_FEATURE_SHM_BUFFER |
        WAYEMBED_FEATURE_EMBED_SESSION |
        WAYEMBED_FEATURE_SEAT |
        WAYEMBED_FEATURE_POINTER |
        WAYEMBED_FEATURE_KEYBOARD |
        WAYEMBED_FEATURE_TOUCH |
        WAYEMBED_FEATURE_OUTPUT |
        WAYEMBED_FEATURE_XDG_SHELL |
        WAYEMBED_FEATURE_CLIENT_FD;
    return (flags & expected) == expected;
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

static void on_embed_mapped(void *userdata, wayembed_embed *embed)
{
    (void)userdata;
    if (wayembed_embed_id(embed) != 0) {
        mapped_count += 1;
    }
}

static void on_embed_resized(void *userdata,
                             wayembed_embed *embed,
                             int32_t width,
                             int32_t height)
{
    (void)userdata;
    if (wayembed_embed_id(embed) != 0 && width >= 0 && height >= 0) {
        resized_count += 1;
    }
}

static void on_embed_destroyed(void *userdata, wayembed_embed *embed)
{
    (void)userdata;
    if (wayembed_embed_id(embed) != 0) {
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
    if (wayembed_get_features(NULL)) {
        return 3;
    }
    wayembed_features features;
    features.size = sizeof(features);
    features.version = WAYEMBED_ABI_VERSION;
    features.flags = 0;
    if (!wayembed_get_features(&features) ||
        !check_feature_flags(features.flags)) {
        return 4;
    }
    features.size = offsetof(wayembed_features, flags);
    features.version = WAYEMBED_ABI_VERSION;
    if (wayembed_get_features(&features)) {
        return 5;
    }
    features.size = sizeof(features);
    features.version = WAYEMBED_ABI_VERSION + 1u;
    if (wayembed_get_features(&features)) {
        return 6;
    }

    if (wayembed_server_snapshot(NULL) != NULL) {
        return 7;
    }
    if (wayembed_snapshot_get_counts(NULL, NULL)) {
        return 8;
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
        return 9;
    }

    if (wayembed_server_get_fd(server) < 0) {
        wayembed_server_destroy(server);
        return 10;
    }

    wayembed_snapshot *empty_snapshot = wayembed_server_snapshot(server);
    if (empty_snapshot == NULL) {
        wayembed_server_destroy(server);
        return 11;
    }
    size_t empty_clients = 99;
    if (!snapshot_clients(empty_snapshot, &empty_clients) || empty_clients != 0) {
        wayembed_snapshot_free(empty_snapshot);
        wayembed_server_destroy(server);
        return 12;
    }
    wayembed_snapshot_counts invalid_counts;
    invalid_counts.size = offsetof(wayembed_snapshot_counts, outputs);
    invalid_counts.version = WAYEMBED_ABI_VERSION;
    if (wayembed_snapshot_get_counts(empty_snapshot, &invalid_counts)) {
        wayembed_snapshot_free(empty_snapshot);
        wayembed_server_destroy(server);
        return 13;
    }
    invalid_counts.size = sizeof(invalid_counts);
    invalid_counts.version = WAYEMBED_ABI_VERSION + 1u;
    if (wayembed_snapshot_get_counts(empty_snapshot, &invalid_counts)) {
        wayembed_snapshot_free(empty_snapshot);
        wayembed_server_destroy(server);
        return 14;
    }
    wayembed_snapshot_free(empty_snapshot);

    /* open/close cycle. */
    struct wl_display *display = wayembed_server_open_client_display(server);
    if (display == NULL) {
        wayembed_server_destroy(server);
        return 15;
    }
    if (wl_display_get_fd(display) < 0) {
        wayembed_server_destroy(server);
        return 16;
    }
    wayembed_server_dispatch(server);
    if (connected_count != 1 || last_client == NULL) {
        wayembed_server_destroy(server);
        return 17;
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
        return 18;
    }
    if (!wayembed_adapter_handoff_init(&handoff,
        WAYEMBED_ADAPTER_FORMAT_CLAP,
        server,
        display)) {
        wayembed_server_destroy(server);
        return 19;
    }
    if (!wayembed_adapter_handoff_validate(&handoff) ||
        handoff.version != WAYEMBED_ADAPTER_ABI_VERSION ||
        handoff.format != WAYEMBED_ADAPTER_FORMAT_CLAP ||
        handoff.display != display ||
        handoff.format_token == NULL ||
        strcmp(handoff.format_token, WAYEMBED_ADAPTER_CLAP_EXPERIMENTAL_API) != 0) {
        wayembed_server_destroy(server);
        return 20;
    }
    handoff.format_token = WAYEMBED_ADAPTER_LV2_EXPERIMENTAL_URI;
    if (wayembed_adapter_handoff_validate(&handoff)) {
        wayembed_server_destroy(server);
        return 21;
    }
    if (!wayembed_adapter_handoff_init(&handoff,
        WAYEMBED_ADAPTER_FORMAT_LV2,
        server,
        display)) {
        wayembed_server_destroy(server);
        return 22;
    }
    if (!wayembed_adapter_handoff_validate(&handoff) ||
        handoff.version != WAYEMBED_ADAPTER_ABI_VERSION ||
        handoff.format != WAYEMBED_ADAPTER_FORMAT_LV2 ||
        handoff.display != display ||
        handoff.format_token == NULL ||
        strcmp(handoff.format_token, WAYEMBED_ADAPTER_LV2_EXPERIMENTAL_URI) != 0) {
        wayembed_server_destroy(server);
        return 23;
    }
    handoff.format_token = WAYEMBED_ADAPTER_CLAP_EXPERIMENTAL_API;
    if (wayembed_adapter_handoff_validate(&handoff)) {
        wayembed_server_destroy(server);
        return 24;
    }
    if (!wayembed_adapter_handoff_init(&handoff,
        WAYEMBED_ADAPTER_FORMAT_VST3,
        server,
        display)) {
        wayembed_server_destroy(server);
        return 25;
    }
    if (!wayembed_adapter_handoff_validate(&handoff) ||
        handoff.version != WAYEMBED_ADAPTER_ABI_VERSION ||
        handoff.format != WAYEMBED_ADAPTER_FORMAT_VST3 ||
        handoff.display != display ||
        handoff.format_token == NULL ||
        strcmp(handoff.format_token,
               WAYEMBED_ADAPTER_VST3_PLATFORM_TYPE_WAYLAND_SURFACE_ID) != 0) {
        wayembed_server_destroy(server);
        return 26;
    }
    handoff.version = WAYEMBED_ADAPTER_ABI_VERSION + 1u;
    if (wayembed_adapter_handoff_validate(&handoff)) {
        wayembed_server_destroy(server);
        return 27;
    }
    if (wayembed_adapter_handoff_init(&handoff,
                                     WAYEMBED_ADAPTER_FORMAT_UNKNOWN,
                                     server,
                                     display)) {
        wayembed_server_destroy(server);
        return 28;
    }

    wayembed_adapter_resize resize;
    resize.size = sizeof(resize);
    resize.version = WAYEMBED_ADAPTER_ABI_VERSION;
    resize.width = 640;
    resize.height = 480;
    resize.scale = 1.0;
    if (!wayembed_adapter_resize_validate(&resize)) {
        wayembed_server_destroy(server);
        return 29;
    }
    resize.width = -1;
    if (wayembed_adapter_resize_validate(&resize)) {
        wayembed_server_destroy(server);
        return 30;
    }
    resize.width = 640;
    resize.scale = 0.0;
    if (wayembed_adapter_resize_validate(&resize)) {
        wayembed_server_destroy(server);
        return 31;
    }
    resize.scale = INFINITY;
    if (wayembed_adapter_resize_validate(&resize)) {
        wayembed_server_destroy(server);
        return 32;
    }
    resize.scale = NAN;
    if (wayembed_adapter_resize_validate(&resize)) {
        wayembed_server_destroy(server);
        return 33;
    }

    wayembed_snapshot *open_snapshot = wayembed_server_snapshot(server);
    if (open_snapshot == NULL) {
        wayembed_server_destroy(server);
        return 34;
    }
    size_t open_clients = 0;
    if (!snapshot_clients(open_snapshot, &open_clients) || open_clients != 1) {
        wayembed_snapshot_free(open_snapshot);
        wayembed_server_destroy(server);
        return 35;
    }
    if (!wayembed_server_close_client_display(server, display)) {
        wayembed_snapshot_free(open_snapshot);
        wayembed_server_destroy(server);
        return 36;
    }
    wayembed_server_dispatch(server);
    if (closed_count != 1) {
        wayembed_snapshot_free(open_snapshot);
        wayembed_server_destroy(server);
        return 37;
    }
    if (mapped_count != 0 || resized_count != 0 || destroyed_count != 0) {
        wayembed_snapshot_free(open_snapshot);
        wayembed_server_destroy(server);
        return 38;
    }

    size_t still_open_clients = 0;
    if (!snapshot_clients(open_snapshot, &still_open_clients) ||
        still_open_clients != 1) {
        wayembed_snapshot_free(open_snapshot);
        wayembed_server_destroy(server);
        return 39;
    }
    wayembed_snapshot_free(open_snapshot);

    wayembed_snapshot *closed_snapshot = wayembed_server_snapshot(server);
    if (closed_snapshot == NULL) {
        wayembed_server_destroy(server);
        return 40;
    }
    size_t closed_clients = 99;
    if (!snapshot_clients(closed_snapshot, &closed_clients) ||
        closed_clients != 0) {
        wayembed_snapshot_free(closed_snapshot);
        wayembed_server_destroy(server);
        return 41;
    }
    wayembed_snapshot_free(closed_snapshot);

    /* fd handoff cycle, explicit close. */
    wayembed_client *fd_client = NULL;
    if (wayembed_server_open_client_fd(NULL, &fd_client) != -1) {
        wayembed_server_destroy(server);
        return 39;
    }
    if (wayembed_server_open_client_fd(server, NULL) != -1) {
        wayembed_server_destroy(server);
        return 40;
    }
    if (wayembed_server_close_client(NULL, NULL)) {
        wayembed_server_destroy(server);
        return 41;
    }

    int client_fd = wayembed_server_open_client_fd(server, &fd_client);
    if (client_fd < 0 || fd_client == NULL) {
        wayembed_server_destroy(server);
        return 42;
    }
    wayembed_adapter_fd_handoff fd_handoff;
    fd_handoff.size = sizeof(fd_handoff);
    fd_handoff.version = 0;
    fd_handoff.format = WAYEMBED_ADAPTER_FORMAT_UNKNOWN;
    fd_handoff.server = NULL;
    fd_handoff.client = NULL;
    fd_handoff.client_fd = -1;
    fd_handoff.format_token = NULL;
    fd_handoff.format_userdata = NULL;
    if (wayembed_adapter_fd_handoff_validate(NULL)) {
        close(client_fd);
        wayembed_server_destroy(server);
        return 42;
    }
    if (!wayembed_adapter_fd_handoff_init(&fd_handoff,
        WAYEMBED_ADAPTER_FORMAT_CLAP,
        server,
        fd_client,
        client_fd)) {
        close(client_fd);
        wayembed_server_destroy(server);
        return 42;
    }
    if (!wayembed_adapter_fd_handoff_validate(&fd_handoff) ||
        fd_handoff.version != WAYEMBED_ADAPTER_ABI_VERSION ||
        fd_handoff.format != WAYEMBED_ADAPTER_FORMAT_CLAP ||
        fd_handoff.client != fd_client ||
        fd_handoff.client_fd != client_fd ||
        fd_handoff.format_token == NULL ||
        strcmp(fd_handoff.format_token, WAYEMBED_ADAPTER_CLAP_EXPERIMENTAL_API) != 0) {
        close(client_fd);
        wayembed_server_destroy(server);
        return 42;
    }
    fd_handoff.format_token = WAYEMBED_ADAPTER_LV2_EXPERIMENTAL_URI;
    if (wayembed_adapter_fd_handoff_validate(&fd_handoff)) {
        close(client_fd);
        wayembed_server_destroy(server);
        return 42;
    }
    if (!wayembed_adapter_fd_handoff_init(&fd_handoff,
        WAYEMBED_ADAPTER_FORMAT_VST3,
        server,
        fd_client,
        client_fd) ||
        !wayembed_adapter_fd_handoff_validate(&fd_handoff)) {
        close(client_fd);
        wayembed_server_destroy(server);
        return 42;
    }
    fd_handoff.version = WAYEMBED_ADAPTER_ABI_VERSION + 1u;
    if (wayembed_adapter_fd_handoff_validate(&fd_handoff)) {
        close(client_fd);
        wayembed_server_destroy(server);
        return 42;
    }
    wayembed_server_dispatch(server);
    if (connected_count != 2 || last_client != fd_client) {
        close(client_fd);
        wayembed_server_destroy(server);
        return 43;
    }
    if (!wayembed_server_close_client(server, fd_client)) {
        close(client_fd);
        wayembed_server_destroy(server);
        return 44;
    }
    if (wayembed_server_close_client(server, fd_client)) {
        close(client_fd);
        wayembed_server_destroy(server);
        return 45;
    }
    close(client_fd);
    wayembed_server_dispatch(server);
    if (closed_count != 2) {
        wayembed_server_destroy(server);
        return 46;
    }

    /* fd handoff cycle, remote fd close. */
    fd_client = NULL;
    client_fd = wayembed_server_open_client_fd(server, &fd_client);
    if (client_fd < 0 || fd_client == NULL) {
        wayembed_server_destroy(server);
        return 47;
    }
    wayembed_server_dispatch(server);
    if (connected_count != 3 || last_client != fd_client) {
        close(client_fd);
        wayembed_server_destroy(server);
        return 48;
    }
    close(client_fd);
    wayembed_server_dispatch(server);
    if (closed_count != 3) {
        wayembed_server_destroy(server);
        return 49;
    }

    /* Embed operations reject invalid handles and structs with status codes. */
    wayembed_embed *embed = NULL;
    if (wayembed_embed_attach(NULL, &embed) !=
        WAYEMBED_EMBED_STATUS_INVALID_ARGUMENT) {
        wayembed_server_destroy(server);
        return 50;
    }
    wayembed_embed_attach_info attach_info;
    attach_info.size = offsetof(wayembed_embed_attach_info, child_surface);
    attach_info.version = WAYEMBED_ABI_VERSION;
    attach_info.client = last_client;
    attach_info.parent_surface = NULL;
    attach_info.child_surface = NULL;
    if (wayembed_embed_attach(&attach_info, &embed) !=
        WAYEMBED_EMBED_STATUS_INVALID_ARGUMENT) {
        wayembed_server_destroy(server);
        return 51;
    }
    attach_info.size = sizeof(attach_info);
    attach_info.version = WAYEMBED_ABI_VERSION + 1u;
    if (wayembed_embed_attach(&attach_info, &embed) !=
        WAYEMBED_EMBED_STATUS_INVALID_ARGUMENT) {
        wayembed_server_destroy(server);
        return 52;
    }
    if (wayembed_embed_resize(NULL, 0, 0) !=
        WAYEMBED_EMBED_STATUS_INVALID_ARGUMENT) {
        wayembed_server_destroy(server);
        return 53;
    }
    if (wayembed_embed_id(NULL) != 0 ||
        wayembed_embed_client(NULL) != NULL) {
        wayembed_server_destroy(server);
        return 54;
    }

    wayembed_server_destroy(server);
    return 0;
}
