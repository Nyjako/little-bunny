#ifndef BUNNY_TEST_HTTP_SERVER_H
#define BUNNY_TEST_HTTP_SERVER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * A minimal, test-only HTTP/1.1 server -- this project's own vendored curl
 * build has CURL_DISABLE_FILE ON (deliberately, as a hardening measure:
 * this app only ever does HTTPS JSON/binary GETs, so file:// support is
 * pure attack surface with no legitimate use), so a C test exercising
 * bunny_download_fetch/bunny_core_download_start can't use file:// URLs
 * the way a quick first draft assumed -- it needs a real (if tiny and
 * local-only) HTTP responder instead. POSIX sockets only, no Windows
 * support -- `make test-c` only ever runs on Linux (test.yml), and the
 * `windows` Makefile target builds with BUNNY_BUILD_TESTS=OFF, so this file
 * is never compiled there either.
 *
 * Serves the exact same (status, body) response to every connection it
 * accepts, up to request_count times, then its background thread exits --
 * bunny_test_http_server_join blocks until that many requests have been
 * served (a natural synchronization point for a test that already knows
 * how many fetches it's about to make) and frees the server.
 */
typedef struct bunny_test_http_server bunny_test_http_server_t;

/* status_line e.g. "200 OK"; body/body_len may be NULL/0 for an empty body.
 * Returns NULL on a socket/bind failure (treat as a test infra failure,
 * not something to retry). */
bunny_test_http_server_t *bunny_test_http_server_start(const char *status_line, const char *body, size_t body_len, int request_count);

/* The server's own "http://127.0.0.1:<port>/" base URL -- caller must
 * free(). Valid immediately after start() returns non-NULL. */
char *bunny_test_http_server_url(bunny_test_http_server_t *server);

/* Blocks until request_count requests have been served, joins the
 * background thread, and frees server. */
void bunny_test_http_server_join(bunny_test_http_server_t *server);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_TEST_HTTP_SERVER_H */
