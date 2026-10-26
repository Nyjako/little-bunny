#include "qr.h"

#include <bunny_common/http.h>
#include <cJSON.h>
#include <goblin/appdirs.h>
#include <goblin/cstr.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/x509.h>
#include <qrcodegen.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "auth.h"
#include "tls.h"

/* qr.c is the only translation unit that includes stb_image_write.h, and
 * it only ever compiles into the single bunny_server_lib static library
 * target -- safe to define the implementation here with no risk of the
 * duplicate-symbol problem a header-only lib's IMPLEMENTATION macro can
 * cause if multiple static libraries in the same link graph each define
 * it independently. */
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include <stb_image_write.h>

char *server_qr_build_connection_json(const char *server_url, const char *bearer_token, const char *cert_sha256)
{
    cJSON *json = cJSON_CreateObject();
    if (!json) {
        return NULL;
    }
    cJSON_AddStringToObject(json, "server_url", server_url ? server_url : "");
    cJSON_AddStringToObject(json, "bearer_token", bearer_token ? bearer_token : "");
    cJSON_AddStringToObject(json, "cert_sha256", cert_sha256 ? cert_sha256 : "");
    char *payload = cJSON_PrintUnformatted(json);
    cJSON_Delete(json);
    return payload;
}

/* Same lookup deploy/dump_server_info.sh already does manually
 * (`curl https://ipinfo.io/ip`) -- `hostname -I`-style local-interface
 * addresses are useless here, clients connect from outside this machine.
 * Not static -- status.c (`bunny_server --status`, M58 follow-up) reuses it
 * too, needing exactly the same fact. */
char *fetch_public_ip(const bunny_http_transport_t *transport, const char *user_agent)
{
    bunny_http_header_t headers[] = {{"User-Agent", user_agent}};
    bunny_http_request_t request = {
        .method = BUNNY_HTTP_GET,
        .url = "https://ipinfo.io/ip",
        .headers = headers,
        .header_count = 1,
        .body = NULL,
        .body_len = 0,
    };
    bunny_http_response_t response;
    if (bunny_http_send(transport, &request, &response) != BUNNY_HTTP_OK || response.status != 200) {
        bunny_http_response_free(&response);
        return NULL;
    }
    char *ip = goblin_copy_cstr(response.body);
    bunny_http_response_free(&response);
    if (!ip) {
        return NULL;
    }
    /* Strip the trailing newline ipinfo.io's plain-text response ends with. */
    size_t len = strlen(ip);
    while (len > 0 && (ip[len - 1] == '\n' || ip[len - 1] == '\r')) {
        ip[--len] = '\0';
    }
    return ip;
}

/* Not static -- status.c reuses this too (see fetch_public_ip's own note
 * above). */
char *compute_cert_sha256(const char *data_dir)
{
    char *pem_path = goblin_appdir_join(data_dir, "server.pem");
    if (!pem_path) {
        return NULL;
    }
    FILE *f = fopen(pem_path, "r");
    free(pem_path);
    if (!f) {
        return NULL;
    }
    X509 *cert = PEM_read_X509(f, NULL, NULL, NULL);
    fclose(f);
    if (!cert) {
        return NULL;
    }

    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int digest_len = 0;
    bool ok = X509_digest(cert, EVP_sha256(), digest, &digest_len) == 1;
    X509_free(cert);
    if (!ok) {
        return NULL;
    }

    char *hex = malloc((size_t)digest_len * 2 + 1);
    if (!hex) {
        return NULL;
    }
    for (unsigned int i = 0; i < digest_len; i++) {
        snprintf(hex + i * 2, 3, "%02X", digest[i]);
    }
    return hex;
}

/* Two module-rows per printed line via Unicode half-block characters
 * (one character per module column, not two) -- quarters the terminal
 * footprint of the old 2-chars-per-module/1-row-per-line rendering, which
 * was "pretty massive" for a typical connection payload's QR version. A
 * typical monospace cell's ~2:1 height:width ratio makes one such cell
 * (covering a 1-wide/2-tall module pair) roughly square. */
static void print_qr(const uint8_t *qrcode)
{
    int size = qrcodegen_getSize(qrcode);
    int border = 2;
    for (int y = -border; y < size + border; y += 2) {
        for (int x = -border; x < size + border; x++) {
            bool top = qrcodegen_getModule(qrcode, x, y);
            bool bottom = qrcodegen_getModule(qrcode, x, y + 1);
            fputs(top ? (bottom ? "█" : "▀") : (bottom ? "▄" : " "), stdout);
        }
        fputs("\n", stdout);
    }
}

/* Growable buffer for stbi_write_png_to_func's callback to accumulate
 * into -- the callback fires once per internal zlib flush (typically a few
 * KB at a time for a QR-sized image), not once per byte, so one memcpy per
 * invocation is enough; no need for goblin/dyn_array.h's single-element
 * _push here. */
typedef struct
{
    uint8_t *data;
    size_t len;
    size_t cap;
} png_buf_t;

static void png_write_callback(void *context, void *data, int size)
{
    png_buf_t *buf = (png_buf_t *)context;
    if (size <= 0) {
        return;
    }
    size_t needed = buf->len + (size_t)size;
    if (needed > buf->cap) {
        size_t new_cap = buf->cap ? buf->cap * 2 : 4096;
        while (new_cap < needed) {
            new_cap *= 2;
        }
        uint8_t *new_data = realloc(buf->data, new_cap);
        if (!new_data) {
            return; /* buf->len stays short of what was written -- caller's length check below catches this */
        }
        buf->data = new_data;
        buf->cap = new_cap;
    }
    memcpy(buf->data + buf->len, data, (size_t)size);
    buf->len += (size_t)size;
}

bool server_qr_render_png(const uint8_t *qrcode, uint8_t **out_data, size_t *out_len)
{
    int size = qrcodegen_getSize(qrcode);
    int border = 2;
    int scale = 8;
    int dim = (size + 2 * border) * scale;

    uint8_t *pixels = malloc((size_t)dim * (size_t)dim);
    if (!pixels) {
        return false;
    }
    for (int my = -border; my < size + border; my++) {
        for (int mx = -border; mx < size + border; mx++) {
            uint8_t shade = qrcodegen_getModule(qrcode, mx, my) ? 0x00 : 0xFF;
            int px0 = (mx + border) * scale;
            int py0 = (my + border) * scale;
            for (int dy = 0; dy < scale; dy++) {
                memset(pixels + (size_t)(py0 + dy) * (size_t)dim + (size_t)px0, shade, (size_t)scale);
            }
        }
    }

    png_buf_t buf = {0};
    int ok = stbi_write_png_to_func(png_write_callback, &buf, dim, dim, 1, pixels, dim);
    free(pixels);
    if (!ok || buf.len == 0) {
        free(buf.data);
        return false;
    }

    *out_data = buf.data;
    *out_len = buf.len;
    return true;
}

bool server_print_connection_qr(const server_config_t *config)
{
    if (!config) {
        return false;
    }

    server_auth_t *auth = server_auth_load(config->data_dir);
    char *cert_path = server_tls_ensure_cert(config->data_dir);
    free(cert_path);
    if (!auth) {
        fprintf(stderr, "qr: failed to load/generate the auth token\n");
        return false;
    }
    if (!cert_path) {
        fprintf(stderr, "qr: failed to generate/locate the TLS certificate\n");
        server_auth_free(auth);
        return false;
    }

    char *cert_sha256 = compute_cert_sha256(config->data_dir);
    if (!cert_sha256) {
        fprintf(stderr, "qr: failed to read server.pem for its fingerprint\n");
        server_auth_free(auth);
        return false;
    }

    bunny_http_transport_t transport = bunny_http_curl_transport();
    char *public_ip = fetch_public_ip(&transport, config->user_agent);
    if (!public_ip) {
        fprintf(stderr, "qr: failed to determine this server's public IP (no internet access?)\n");
        free(cert_sha256);
        server_auth_free(auth);
        return false;
    }

    char server_url[256];
    snprintf(server_url, sizeof(server_url), "https://%s:%d", public_ip, config->port);
    free(public_ip);

    char *payload = server_qr_build_connection_json(server_url, auth->token, cert_sha256);
    free(cert_sha256);
    server_auth_free(auth);
    if (!payload) {
        fprintf(stderr, "qr: failed to build the connection JSON payload\n");
        return false;
    }

    uint8_t qrcode[qrcodegen_BUFFER_LEN_MAX];
    uint8_t temp_buffer[qrcodegen_BUFFER_LEN_MAX];
    bool encoded =
        qrcodegen_encodeText(payload, temp_buffer, qrcode, qrcodegen_Ecc_LOW, qrcodegen_VERSION_MIN, qrcodegen_VERSION_MAX, qrcodegen_Mask_AUTO, true);
    if (!encoded) {
        fprintf(stderr, "qr: connection info is too large to encode as a QR code\n");
        free(payload);
        return false;
    }

    printf("Scan this with the LittleBunny app's \"Networked\" setup to connect automatically:\n\n");
    print_qr(qrcode);
    printf("\nOr enter these manually:\n%s\n", payload);
    free(payload);
    return true;
}
