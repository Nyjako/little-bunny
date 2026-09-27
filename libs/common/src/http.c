#include "bunny_common/http.h"

#include <curl/curl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char *data;
    size_t len;
    size_t cap;
} growable_buf_t;

static size_t write_cb(char *ptr, size_t size, size_t nmemb, void *userdata) {
    growable_buf_t *buf = (growable_buf_t *)userdata;
    size_t add = size * nmemb;

    if (buf->len + add + 1 > buf->cap) {
        size_t new_cap = buf->cap == 0 ? 4096 : buf->cap * 2;
        while (new_cap < buf->len + add + 1) {
            new_cap *= 2;
        }
        char *new_data = realloc(buf->data, new_cap);
        if (!new_data) {
            return 0; /* signals an error to curl, aborts the transfer */
        }
        buf->data = new_data;
        buf->cap = new_cap;
    }

    memcpy(buf->data + buf->len, ptr, add);
    buf->len += add;
    buf->data[buf->len] = '\0';
    return add;
}

static void ensure_curl_global_init(void) {
    static int initialized = 0;
    if (!initialized) {
        curl_global_init(CURL_GLOBAL_DEFAULT);
        initialized = 1;
    }
}

static struct curl_slist *build_header_list(const bunny_http_request_t *request) {
    struct curl_slist *list = NULL;
    for (size_t i = 0; i < request->header_count; i++) {
        const char *name = request->headers[i].name;
        const char *value = request->headers[i].value;
        size_t needed = strlen(name) + strlen(value) + 3; /* ": " + NUL */
        char *line = malloc(needed);
        if (!line) {
            continue;
        }
        snprintf(line, needed, "%s: %s", name, value);
        list = curl_slist_append(list, line);
        free(line); /* curl_slist_append copies the string */
    }
    return list;
}

static bunny_http_result_t curl_send(void *user_data,
                                      const bunny_http_request_t *request,
                                      bunny_http_response_t *out_response) {
    (void)user_data;
    if (!request || !request->url || !out_response) {
        return BUNNY_HTTP_ERR_INVALID_ARG;
    }

    ensure_curl_global_init();

    CURL *curl = curl_easy_init();
    if (!curl) {
        return BUNNY_HTTP_ERR_NETWORK;
    }

    growable_buf_t buf = {0};
    struct curl_slist *header_list = build_header_list(request);

    curl_easy_setopt(curl, CURLOPT_URL, request->url);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &buf);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30L);

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
        /* keep body non-NULL and NUL-terminated even for empty responses */
        out_response->body = buf.data ? buf.data : calloc(1, 1);
    }

    if (header_list) {
        curl_slist_free_all(header_list);
    }
    curl_easy_cleanup(curl);

    return result;
}

bunny_http_transport_t bunny_http_curl_transport(void) {
    bunny_http_transport_t transport;
    transport.send = curl_send;
    transport.user_data = NULL;
    return transport;
}

bunny_http_result_t bunny_http_send(const bunny_http_transport_t *transport,
                                     const bunny_http_request_t *request,
                                     bunny_http_response_t *out_response) {
    if (!transport || !transport->send || !request || !out_response) {
        return BUNNY_HTTP_ERR_INVALID_ARG;
    }
    memset(out_response, 0, sizeof(*out_response));
    return transport->send(transport->user_data, request, out_response);
}

void bunny_http_response_free(bunny_http_response_t *response) {
    if (!response) {
        return;
    }
    free(response->body);
    response->body = NULL;
    response->body_len = 0;
}
