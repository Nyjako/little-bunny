#include "rest_client.h"

#include <curl/curl.h>
#include <openssl/evp.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- certificate pinning (production transport only) ------------------- */

/* The server's cert is self-signed with no CA (docs/architecture.md's TLS
 * section) -- there is nothing for normal chain validation to check
 * against, so it's disabled entirely (CURLOPT_SSL_VERIFYPEER/VERIFYHOST
 * below) and replaced with our own OpenSSL-level verify callback that
 * accepts a connection if and only if the presented leaf certificate's
 * SHA-256 digest matches the fingerprint the handshake reported. This is
 * trust-on-first-use, the same shape as SSH host keys -- not the web PKI.
 *
 * A plain static buffer, not something threaded through curl's per-request
 * user-data: bunny_common's own curl transport is already documented as
 * "not thread-safe, one request in flight per process at a time"
 * (bunny_http_curl_transport's doc comment) and bunny_cli never issues REST
 * calls from more than one thread, so this matches that existing
 * precedent rather than inventing a new threading rule just for this one
 * transport. */
static char g_pinned_fingerprint_hex[65]; /* 32 bytes of SHA-256, hex, no colons, lowercase */

static void normalize_fingerprint_hex(const char *input, char *out_hex65)
{
    size_t out_len = 0;
    for (const char *p = input; *p && out_len < 64; p++) {
        if (*p == ':') {
            continue;
        }
        out_hex65[out_len++] = (char)tolower((unsigned char)*p);
    }
    out_hex65[out_len] = '\0';
}

/* Pure, testable comparison: does `digest` (32 raw SHA-256 bytes) match the
 * hex fingerprint `expected` (colons/case tolerated)? Factored out of the
 * OpenSSL verify callback below so the actual byte-to-hex-and-compare logic
 * gets automated coverage without needing a real TLS handshake -- the same
 * reasoning as app/lib/repository/http_bunny_repository.dart's own
 * standalone matchesPinnedFingerprint function. */
bool bunny_cli_rest_fingerprint_matches(const unsigned char *digest, size_t digest_len, const char *expected_hex)
{
    if (!digest || !expected_hex || digest_len != 32) {
        return false;
    }
    char actual_hex[65];
    for (size_t i = 0; i < digest_len; i++) {
        snprintf(actual_hex + i * 2, 3, "%02x", digest[i]);
    }
    char normalized_expected[65];
    normalize_fingerprint_hex(expected_hex, normalized_expected);
    return strcmp(actual_hex, normalized_expected) == 0;
}

static int pinned_verify_callback(int preverify_ok, X509_STORE_CTX *x509_ctx)
{
    (void)preverify_ok; /* chain validity is meaningless for a self-signed cert with no CA */
    if (X509_STORE_CTX_get_error_depth(x509_ctx) != 0) {
        return 1; /* only the leaf (depth 0) is the server's own cert */
    }

    X509 *cert = X509_STORE_CTX_get_current_cert(x509_ctx);
    if (!cert) {
        return 0;
    }

    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int digest_len = 0;
    if (!X509_digest(cert, EVP_sha256(), digest, &digest_len)) {
        return 0;
    }

    return bunny_cli_rest_fingerprint_matches(digest, digest_len, g_pinned_fingerprint_hex) ? 1 : 0;
}

static CURLcode pinned_ssl_ctx_callback(CURL *curl, void *ssl_ctx, void *parm)
{
    (void)curl;
    (void)parm;
    SSL_CTX_set_verify((SSL_CTX *)ssl_ctx, SSL_VERIFY_PEER, pinned_verify_callback);
    return CURLE_OK;
}

/* ---- the curl transport (shared shape with bunny_http_curl_transport, --
 * libs/common/src/http.c -- re-implemented locally rather than extended
 * there; see rest_client.h's doc comment on why pinning can't live in
 * bunny_common) --------------------------------------------------------- */

typedef struct
{
    char *data;
    size_t len;
    size_t cap;
} growable_buf_t;

static size_t write_cb(char *ptr, size_t size, size_t nmemb, void *userdata)
{
    growable_buf_t *buf = (growable_buf_t *)userdata;
    size_t add = size * nmemb;

    if (buf->len + add + 1 > buf->cap) {
        size_t new_cap = buf->cap == 0 ? 4096 : buf->cap * 2;
        while (new_cap < buf->len + add + 1) {
            new_cap *= 2;
        }
        char *new_data = realloc(buf->data, new_cap);
        if (!new_data) {
            return 0;
        }
        buf->data = new_data;
        buf->cap = new_cap;
    }

    memcpy(buf->data + buf->len, ptr, add);
    buf->len += add;
    buf->data[buf->len] = '\0';
    return add;
}

static struct curl_slist *build_header_list(const bunny_http_request_t *request)
{
    struct curl_slist *list = NULL;
    for (size_t i = 0; i < request->header_count; i++) {
        const char *name = request->headers[i].name;
        const char *value = request->headers[i].value;
        size_t needed = strlen(name) + strlen(value) + 3;
        char *line = malloc(needed);
        if (!line) {
            continue;
        }
        snprintf(line, needed, "%s: %s", name, value);
        list = curl_slist_append(list, line);
        free(line);
    }
    return list;
}

typedef struct
{
    char fingerprint_hex[65];
} pinned_transport_data_t;

static bunny_http_result_t pinned_curl_send(void *user_data, const bunny_http_request_t *request, bunny_http_response_t *out_response)
{
    if (!request || !request->url || !out_response) {
        return BUNNY_HTTP_ERR_INVALID_ARG;
    }

    pinned_transport_data_t *data = (pinned_transport_data_t *)user_data;
    strncpy(g_pinned_fingerprint_hex, data->fingerprint_hex, sizeof(g_pinned_fingerprint_hex) - 1);
    g_pinned_fingerprint_hex[sizeof(g_pinned_fingerprint_hex) - 1] = '\0';

    CURL *curl = curl_easy_init();
    if (!curl) {
        return BUNNY_HTTP_ERR_NETWORK;
    }

    growable_buf_t buf = {0};
    struct curl_slist *header_list = build_header_list(request);

    curl_easy_setopt(curl, CURLOPT_URL, request->url);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &buf);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 0L); /* never follow a redirect to an unpinned host */
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30L);

    /* No CA to validate against (self-signed, M5's own TLS design) -- our
     * SSL_CTX_FUNCTION callback above replaces libcurl's own verification
     * with the fingerprint check instead of skipping verification outright. */
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);
    curl_easy_setopt(curl, CURLOPT_SSL_CTX_FUNCTION, pinned_ssl_ctx_callback);

    switch (request->method) {
        case BUNNY_HTTP_GET:
            break;
        case BUNNY_HTTP_POST:
            curl_easy_setopt(curl, CURLOPT_POST, 1L);
            break;
        case BUNNY_HTTP_PUT:
            curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "PUT");
            break;
        case BUNNY_HTTP_DELETE:
            curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "DELETE");
            break;
    }

    if (request->body && request->body_len > 0) {
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, request->body);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)request->body_len);
    }

    if (header_list) {
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, header_list);
    }

    CURLcode res = curl_easy_perform(curl);

    bunny_http_result_t result = BUNNY_HTTP_OK;
    if (res != CURLE_OK) {
        result = BUNNY_HTTP_ERR_NETWORK;
        free(buf.data);
        out_response->status = 0;
        out_response->body = NULL;
        out_response->body_len = 0;
    } else {
        long status = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
        out_response->status = status;
        out_response->body_len = buf.len;
        out_response->body = buf.data ? buf.data : calloc(1, 1);
    }

    if (header_list) {
        curl_slist_free_all(header_list);
    }
    curl_easy_cleanup(curl);

    return result;
}

/* ---- client lifecycle --------------------------------------------------- */

bool bunny_cli_rest_client_init(bunny_cli_rest_client_t *client, const char *base_url, const char *bearer_token, const char *cert_fingerprint)
{
    if (!client || !base_url || !*base_url || !bearer_token || !*bearer_token || !cert_fingerprint || !*cert_fingerprint) {
        return false;
    }

    bunny_http_global_init();

    pinned_transport_data_t *data = malloc(sizeof(pinned_transport_data_t));
    if (!data) {
        return false;
    }
    normalize_fingerprint_hex(cert_fingerprint, data->fingerprint_hex);

    client->base_url = strdup(base_url);
    client->bearer_token = strdup(bearer_token);
    client->transport.send = pinned_curl_send;
    client->transport.user_data = data;
    client->owns_transport_fingerprint = true;
    return client->base_url != NULL && client->bearer_token != NULL;
}

void bunny_cli_rest_client_init_with_transport(bunny_cli_rest_client_t *client, const char *base_url, const char *bearer_token, bunny_http_transport_t transport)
{
    client->base_url = strdup(base_url);
    client->bearer_token = strdup(bearer_token);
    client->transport = transport;
    client->owns_transport_fingerprint = false;
}

void bunny_cli_rest_client_free(bunny_cli_rest_client_t *client)
{
    if (!client) {
        return;
    }
    free(client->base_url);
    free(client->bearer_token);
    if (client->owns_transport_fingerprint) {
        free(client->transport.user_data);
    }
    client->base_url = NULL;
    client->bearer_token = NULL;
    client->transport.user_data = NULL;
}

/* ---- requests ------------------------------------------------------------ */

static bunny_cli_rest_result_t result_for_status(long status)
{
    if (status == 200 || status == 201 || status == 202) {
        return BUNNY_CLI_REST_OK;
    }
    switch (status) {
        case 400:
            return BUNNY_CLI_REST_ERR_INVALID_ARG;
        case 401:
            return BUNNY_CLI_REST_ERR_UNAUTHORIZED;
        case 404:
            return BUNNY_CLI_REST_ERR_NOT_FOUND;
        case 415:
            return BUNNY_CLI_REST_ERR_UNSUPPORTED;
        case 502:
            return BUNNY_CLI_REST_ERR_SITE;
        default:
            return BUNNY_CLI_REST_ERR_SERVER;
    }
}

bunny_cli_rest_result_t bunny_cli_rest_request(bunny_cli_rest_client_t *client, bunny_http_method_t method, const char *path, const cJSON *body, cJSON **out_json)
{
    if (out_json) {
        *out_json = NULL;
    }
    if (!client || !path) {
        return BUNNY_CLI_REST_ERR_INVALID_ARG;
    }

    char url[2048];
    snprintf(url, sizeof(url), "%s%s", client->base_url, path);

    char auth_header_value[600];
    snprintf(auth_header_value, sizeof(auth_header_value), "Bearer %s", client->bearer_token);
    bunny_http_header_t headers[2];
    size_t header_count = 1;
    headers[0].name = "Authorization";
    headers[0].value = auth_header_value;

    char *body_text = NULL;
    if (body) {
        body_text = cJSON_PrintUnformatted(body);
        headers[header_count].name = "Content-Type";
        headers[header_count].value = "application/json";
        header_count++;
    }

    bunny_http_request_t request;
    memset(&request, 0, sizeof(request));
    request.method = method;
    request.url = url;
    request.headers = headers;
    request.header_count = header_count;
    request.body = body_text;
    request.body_len = body_text ? strlen(body_text) : 0;

    bunny_http_response_t response;
    bunny_http_result_t send_result = bunny_http_send(&client->transport, &request, &response);
    free(body_text);

    if (send_result != BUNNY_HTTP_OK) {
        return BUNNY_CLI_REST_ERR_NETWORK;
    }

    cJSON *parsed = response.body_len > 0 ? cJSON_Parse(response.body) : NULL;
    bunny_http_response_free(&response);

    bunny_cli_rest_result_t result = result_for_status(response.status);
    if (out_json) {
        *out_json = parsed;
    } else {
        cJSON_Delete(parsed);
    }
    return result;
}

char *bunny_cli_rest_url_encode(const char *value)
{
    if (!value) {
        return NULL;
    }
    size_t len = strlen(value);
    char *out = malloc(len * 3 + 1);
    if (!out) {
        return NULL;
    }
    size_t out_len = 0;
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)value[i];
        bool unreserved = isalnum(c) || c == '-' || c == '.' || c == '_' || c == '~';
        if (unreserved) {
            out[out_len++] = (char)c;
        } else {
            snprintf(out + out_len, 4, "%%%02X", c);
            out_len += 3;
        }
    }
    out[out_len] = '\0';
    return out;
}

const char *bunny_cli_rest_result_to_string(bunny_cli_rest_result_t result)
{
    switch (result) {
        case BUNNY_CLI_REST_OK:
            return "ok";
        case BUNNY_CLI_REST_ERR_INVALID_ARG:
            return "server rejected the request (invalid argument)";
        case BUNNY_CLI_REST_ERR_UNAUTHORIZED:
            return "server rejected the bearer token (unauthorized)";
        case BUNNY_CLI_REST_ERR_NOT_FOUND:
            return "not found";
        case BUNNY_CLI_REST_ERR_SITE:
            return "the site itself failed (bad gateway)";
        case BUNNY_CLI_REST_ERR_UNSUPPORTED:
            return "unsupported format";
        case BUNNY_CLI_REST_ERR_SERVER:
            return "server error";
        case BUNNY_CLI_REST_ERR_NETWORK:
            return "could not reach the server (network error or certificate mismatch)";
    }
    return "unknown error";
}
