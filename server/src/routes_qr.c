#include "routes_qr.h"

#include <bunny_core/error.h>
#include <cJSON.h>
#include <qrcodegen.h>

#include <stdlib.h>
#include <string.h>

#include "auth.h"
#include "json_helpers.h"
#include "qr.h"

static int handle_post_qr(struct mg_connection *conn, server_context_t *ctx)
{
    (void)ctx;
    cJSON *body = server_json_read_request_body(conn);
    if (!body) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    cJSON *url_item = cJSON_GetObjectItemCaseSensitive(body, "server_url");
    cJSON *token_item = cJSON_GetObjectItemCaseSensitive(body, "bearer_token");
    cJSON *cert_item = cJSON_GetObjectItemCaseSensitive(body, "cert_sha256");
    if (!cJSON_IsString(url_item) || !cJSON_IsString(token_item) || !cJSON_IsString(cert_item) || url_item->valuestring[0] == '\0' ||
        token_item->valuestring[0] == '\0' || cert_item->valuestring[0] == '\0') {
        cJSON_Delete(body);
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    char *payload = server_qr_build_connection_json(url_item->valuestring, token_item->valuestring, cert_item->valuestring);
    cJSON_Delete(body);
    if (!payload) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_UNKNOWN);
    }

    uint8_t qrcode[qrcodegen_BUFFER_LEN_MAX];
    uint8_t temp_buffer[qrcodegen_BUFFER_LEN_MAX];
    bool encoded =
        qrcodegen_encodeText(payload, temp_buffer, qrcode, qrcodegen_Ecc_LOW, qrcodegen_VERSION_MIN, qrcodegen_VERSION_MAX, qrcodegen_Mask_AUTO, true);
    free(payload);
    if (!encoded) {
        /* The only realistic cause: the three fields together are too
         * large for a QR code to hold (qrcodegen's own hard limit). */
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    uint8_t *png_data = NULL;
    size_t png_len = 0;
    if (!server_qr_render_png(qrcode, &png_data, &png_len)) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_UNKNOWN);
    }

    mg_printf(conn, "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: %zu\r\nConnection: close\r\n\r\n", png_len);
    mg_write(conn, png_data, png_len);
    free(png_data);
    return 200;
}

static int qr_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }

    const struct mg_request_info *info = mg_get_request_info(conn);
    if (strcmp(info->request_method, "POST") == 0) {
        return handle_post_qr(conn, ctx);
    }

    return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
}

void server_routes_register_qr(struct mg_context *mg_ctx, server_context_t *ctx)
{
    mg_set_request_handler(mg_ctx, "/qr", qr_handler, ctx);
}
