#ifndef BUNNY_COMMON_HTTP_H
#define BUNNY_COMMON_HTTP_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    BUNNY_HTTP_OK = 0,
    BUNNY_HTTP_ERR_INVALID_ARG,
    BUNNY_HTTP_ERR_NETWORK,
} bunny_http_result_t;

typedef enum {
    BUNNY_HTTP_GET,
    BUNNY_HTTP_POST,
    BUNNY_HTTP_PUT,
    BUNNY_HTTP_DELETE,
} bunny_http_method_t;

typedef struct {
    const char *name;
    const char *value;
} bunny_http_header_t;

typedef struct {
    bunny_http_method_t method;
    const char *url;
    const bunny_http_header_t *headers;
    size_t header_count;
    const char *body; /* may be NULL; not required to be NUL-terminated, use body_len */
    size_t body_len;
} bunny_http_request_t;

typedef struct {
    long status;
    char *body; /* owned by the response, NUL-terminated; free with bunny_http_response_free */
    size_t body_len;
} bunny_http_response_t;

/*
 * A transport is anything that can turn a request into a response.
 * Production code uses bunny_http_curl_transport(); tests inject a fake
 * transport (e.g. one that serves fixture files keyed by URL) so no unit
 * test ever touches the network.
 */
typedef struct {
    bunny_http_result_t (*send)(void *user_data,
                                 const bunny_http_request_t *request,
                                 bunny_http_response_t *out_response);
    void *user_data;
} bunny_http_transport_t;

/* Backed by libcurl. Not thread-safe: at most one request in flight per process at a time. */
bunny_http_transport_t bunny_http_curl_transport(void);

bunny_http_result_t bunny_http_send(const bunny_http_transport_t *transport,
                                     const bunny_http_request_t *request,
                                     bunny_http_response_t *out_response);

void bunny_http_response_free(bunny_http_response_t *response);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_COMMON_HTTP_H */
