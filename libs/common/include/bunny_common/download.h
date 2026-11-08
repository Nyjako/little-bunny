#ifndef BUNNY_COMMON_DOWNLOAD_H
#define BUNNY_COMMON_DOWNLOAD_H

#include <stddef.h>
#include <stdint.h>

#include "bunny_common/http.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * A streaming binary download primitive, parallel to (not an extension of)
 * bunny_http_transport_t -- that one is a single, fully-buffered
 * request/response built for small JSON API calls, and its own doc comment
 * says "not thread-safe: at most one request in flight per process at a
 * time." This primitive instead opens a fresh curl easy handle per call,
 * with no shared/global state at all, which is what makes concurrent calls
 * from separate threads safe without any new locking -- used by the
 * download pipeline (M66) to fetch several files in parallel.
 */

/* Called for each chunk of the response body as it arrives, in order, from
 * the same thread running bunny_download_fetch. Return non-zero to abort
 * the transfer (e.g. a failed disk write). */
typedef int (*bunny_download_chunk_fn)(void *user_data, const void *data, size_t len);

/* Called periodically as bytes arrive, from the same thread running
 * bunny_download_fetch. total is -1 if the server never reported a
 * Content-Length. */
typedef void (*bunny_download_progress_fn)(void *user_data, int64_t received, int64_t total);

typedef struct
{
    bunny_download_chunk_fn on_chunk;
    bunny_download_progress_fn on_progress; /* may be NULL */
    void *user_data;
} bunny_download_sink_t;

/*
 * Streams url's response body through sink->on_chunk as it arrives --
 * never buffers the whole body in memory, unlike bunny_http_send.
 * *out_status receives the HTTP status code once a response is actually
 * received (stays 0 if the transfer never got that far, e.g. a DNS/connect
 * failure). Returns BUNNY_HTTP_ERR_INVALID_ARG if sink/sink->on_chunk/url/
 * out_status is missing, BUNNY_HTTP_ERR_NETWORK for a transport-level
 * failure (including on_chunk returning non-zero to abort), otherwise
 * BUNNY_HTTP_OK regardless of the HTTP status code itself -- a 404/500 is
 * still a successful transfer as far as this function is concerned; the
 * caller inspects *out_status for that.
 */
bunny_http_result_t bunny_download_fetch(const char *url, const bunny_http_header_t *headers, size_t header_count, const bunny_download_sink_t *sink, long *out_status);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_COMMON_DOWNLOAD_H */
