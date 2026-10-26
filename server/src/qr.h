#ifndef BUNNY_SERVER_QR_H
#define BUNNY_SERVER_QR_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "config.h"

/* Builds the JSON payload a QR code encodes for the app's "Networked" setup
 * screen to scan and auto-fill -- {"server_url":...,"bearer_token":...,
 * "cert_sha256":...}, the exact three fields that screen otherwise needs
 * typed in by hand (see deploy/dump_server_info.sh, which surfaces the same
 * three values for manual copy-paste). Returned string is malloc'd, caller
 * frees. NULL on failure (cJSON allocation failure only -- the inputs
 * themselves are never validated, this is pure string-building). */
char *server_qr_build_connection_json(const char *server_url, const char *bearer_token, const char *cert_sha256);

/* Ensures this server's auth token + TLS cert exist (generating them if
 * this is the very first run, same as a normal server start would),
 * determines its own public IP (via the same ipinfo.io lookup
 * deploy/dump_server_info.sh already does manually), and prints a QR code
 * (plus the raw JSON, for manual copy-paste as a fallback) to stdout
 * encoding server_qr_build_connection_json's payload. Returns false on any
 * failure (logged to stderr) -- e.g. no internet access to resolve the
 * public IP. */
bool server_print_connection_qr(const server_config_t *config);

/* Rasterizes an already-encoded qrcodegen module grid (`qrcode`, as
 * returned by `qrcodegen_encodeText`) as a PNG -- 8px per module, border=2
 * (matching `print_qr`'s own border), black/white content as 8-bit
 * grayscale. Used by the `/qr` route (routes_qr.c) so an already-connected
 * app can display its own connection QR without the app needing its own
 * QR-rendering library. On success, `*out_data` is malloc'd (caller frees)
 * and `*out_len` is its length; returns false (leaving both untouched) on
 * a PNG-encoding failure. */
bool server_qr_render_png(const uint8_t *qrcode, uint8_t **out_data, size_t *out_len);

#endif /* BUNNY_SERVER_QR_H */
