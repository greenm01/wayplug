#ifndef WAYPLUG_ADAPTERS_H
#define WAYPLUG_ADAPTERS_H

#include "wayplug.h"

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WAYPLUG_ADAPTER_ABI_VERSION 1u

#define WAYPLUG_ADAPTER_CLAP_EXPERIMENTAL_API "wayplug.experimental.clap.wayland"
#define WAYPLUG_ADAPTER_LV2_EXPERIMENTAL_URI "https://wayplug.org/ns/ext/wayland-ui"

typedef enum wayplug_adapter_format {
    WAYPLUG_ADAPTER_FORMAT_UNKNOWN = 0,
    WAYPLUG_ADAPTER_FORMAT_CLAP = 1,
    WAYPLUG_ADAPTER_FORMAT_LV2 = 2,
} wayplug_adapter_format;

typedef struct wayplug_adapter_handoff {
    uint32_t size;
    uint32_t version;
    uint32_t format;
    wayplug_server *server;
    struct wl_display *display;
    const char *format_token;
    void *format_userdata;
} wayplug_adapter_handoff;

typedef struct wayplug_adapter_resize {
    uint32_t size;
    uint32_t version;
    int32_t width;
    int32_t height;
    double scale;
} wayplug_adapter_resize;

uint32_t wayplug_adapter_abi_version(void);

bool wayplug_adapter_handoff_init(wayplug_adapter_handoff *handoff,
                                  uint32_t format,
                                  wayplug_server *server,
                                  struct wl_display *display);

bool wayplug_adapter_handoff_validate(const wayplug_adapter_handoff *handoff);

bool wayplug_adapter_resize_validate(const wayplug_adapter_resize *resize);

#ifdef __cplusplus
}
#endif

#endif
