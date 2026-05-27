#ifndef WAYEMBED_ADAPTERS_H
#define WAYEMBED_ADAPTERS_H

#include "wayembed.h"

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WAYEMBED_ADAPTER_ABI_VERSION 1u

#define WAYEMBED_ADAPTER_CLAP_EXPERIMENTAL_API "wayembed.experimental.clap.wayland"
#define WAYEMBED_ADAPTER_LV2_EXPERIMENTAL_URI "https://wayembed.org/ns/ext/wayland-ui"

typedef enum wayembed_adapter_format {
    WAYEMBED_ADAPTER_FORMAT_UNKNOWN = 0,
    WAYEMBED_ADAPTER_FORMAT_CLAP = 1,
    WAYEMBED_ADAPTER_FORMAT_LV2 = 2,
} wayembed_adapter_format;

typedef struct wayembed_adapter_handoff {
    uint32_t size;
    uint32_t version;
    uint32_t format;
    wayembed_server *server;
    struct wl_display *display;
    const char *format_token;
    void *format_userdata;
} wayembed_adapter_handoff;

typedef struct wayembed_adapter_resize {
    uint32_t size;
    uint32_t version;
    int32_t width;
    int32_t height;
    double scale;
} wayembed_adapter_resize;

uint32_t wayembed_adapter_abi_version(void);

bool wayembed_adapter_handoff_init(wayembed_adapter_handoff *handoff,
                                  uint32_t format,
                                  wayembed_server *server,
                                  struct wl_display *display);

bool wayembed_adapter_handoff_validate(const wayembed_adapter_handoff *handoff);

bool wayembed_adapter_resize_validate(const wayembed_adapter_resize *resize);

#ifdef __cplusplus
}
#endif

#endif
