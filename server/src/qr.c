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
 * addresses are useless here, clients connect from outside this machine. */
static char *fetch_public_ip(const bunny_http_transport_t *transport, const char *user_agent)
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

static char *compute_cert_sha256(const char *data_dir)
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
