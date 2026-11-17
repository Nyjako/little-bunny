#ifndef BUNNY_CLI_REST_CLIENT_H
#define BUNNY_CLI_REST_CLIENT_H

#include <bunny_common/http.h>
#include <cJSON.h>

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Talks to a bunny_server instance over the exact REST surface documented
 * in docs/architecture.md's "C server (M5)" section -- the networked-mode
 * counterpart to calling bunny_core_* directly in standalone mode. Every
 * route needs "Authorization: Bearer <token>"; the production transport
 * additionally pins the server's self-signed certificate by its SHA-256
 * fingerprint (trust-on-first-use, the same model app/lib/repository/
 * http_bunny_repository.dart's badCertificateCallback uses) since there's
 * no CA to validate against. */
typedef struct
{
    char *base_url;     /* owned, no trailing slash, e.g. "https://1.2.3.4:8443" */
    char *bearer_token; /* owned */
    bunny_http_transport_t transport;
    bool owns_transport_fingerprint; /* true for the real pinned transport, so _free knows to release it */
} bunny_cli_rest_client_t;

typedef enum
{
    BUNNY_CLI_REST_OK = 0,
    BUNNY_CLI_REST_ERR_INVALID_ARG,  /* HTTP 400 */
    BUNNY_CLI_REST_ERR_UNAUTHORIZED, /* HTTP 401 -- bearer token rejected */
    BUNNY_CLI_REST_ERR_NOT_FOUND,    /* HTTP 404 */
    BUNNY_CLI_REST_ERR_SITE,         /* HTTP 502 -- the site itself failed */
    BUNNY_CLI_REST_ERR_UNSUPPORTED,  /* HTTP 415 */
    BUNNY_CLI_REST_ERR_SERVER,       /* any other non-2xx status */
    BUNNY_CLI_REST_ERR_NETWORK,      /* couldn't even reach the server, or its TLS cert didn't match */
    BUNNY_CLI_REST_ERR_IO,           /* bunny_cli_rest_download only -- the response came back fine, but couldn't be written to dest_path */
} bunny_cli_rest_result_t;

/* Builds the real production client: a curl-backed transport that pins
 * `cert_fingerprint` (hex, colons/case-insensitive, same format the
 * handshake payload's cert_fingerprint field already carries) via OpenSSL's
 * own SSL_CTX_set_verify, bypassing libcurl's normal CA-chain validation
 * entirely (there is no CA here, see docs/architecture.md's TLS section).
 * `cert_fingerprint` is copied; the client does not need it to outlive this
 * call. Returns false if any argument is NULL/empty. */
bool bunny_cli_rest_client_init(bunny_cli_rest_client_t *client, const char *base_url, const char *bearer_token, const char *cert_fingerprint);

/* Test-only: injects an arbitrary transport (a fake one keyed by URL, e.g.)
 * instead of the real pinned curl transport -- fakes the transport, not the
 * request-building/response-mapping logic, same philosophy as every other
 * fake transport in this codebase. Never performs a real TLS handshake, so
 * this never exercises bunny_cli_rest_client_init's own pinning code. */
void bunny_cli_rest_client_init_with_transport(bunny_cli_rest_client_t *client, const char *base_url, const char *bearer_token, bunny_http_transport_t transport);

void bunny_cli_rest_client_free(bunny_cli_rest_client_t *client);

/* Issues one request against `client->base_url + path` (`path` must start
 * with '/', and already carry its own query string if it needs one --
 * callers build it with bunny_cli_rest_url_encode below rather than
 * concatenating raw user input). `body`, if non-NULL, is sent as the
 * unformatted JSON request body (owned by the caller, not freed here). On
 * BUNNY_CLI_REST_OK, `*out_json` is the parsed response body (NULL if the
 * server sent no JSON at all, e.g. for an empty response) -- the caller
 * owns it (cJSON_Delete). On any error, `*out_json` is set to the parsed
 * error body if there was one (so the caller can log its "error" field),
 * still owned by the caller. `out_json` may be NULL if the caller only
 * cares about the result code. */
bunny_cli_rest_result_t bunny_cli_rest_request(bunny_cli_rest_client_t *client, bunny_http_method_t method, const char *path, const cJSON *body, cJSON **out_json);

/* Percent-encodes `value` for safe use in a URL path segment or query
 * value (RFC 3986 unreserved characters pass through unchanged, everything
 * else becomes %XX). Returns a newly malloc'd NUL-terminated string the
 * caller must free(); NULL on allocation failure. Needed because tags and
 * search queries can contain spaces/punctuation the server's own
 * mg_get_var parsing expects properly escaped. */
char *bunny_cli_rest_url_encode(const char *value);

/* Like bunny_cli_rest_request, but for a route that returns a raw binary
 * body (e.g. GET /posts/{id}/writing_epub, application/epub+zip) instead
 * of JSON -- the response is streamed straight to dest_path rather than
 * parsed. Always a GET, no request body. Overwrites dest_path if it
 * already exists. */
bunny_cli_rest_result_t bunny_cli_rest_download(bunny_cli_rest_client_t *client, const char *path, const char *dest_path);

const char *bunny_cli_rest_result_to_string(bunny_cli_rest_result_t result);

/* Exposed for testing only: does a raw SHA-256 digest (32 bytes) match a
 * hex fingerprint (colons/case tolerated)? This is the exact comparison
 * the real pinned transport's OpenSSL verify callback uses, factored out
 * so it has automated coverage without a real TLS handshake -- see
 * rest_client.c's own doc comment. */
bool bunny_cli_rest_fingerprint_matches(const unsigned char *digest, size_t digest_len, const char *expected_hex);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_CLI_REST_CLIENT_H */
