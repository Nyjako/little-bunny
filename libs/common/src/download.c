#include "bunny_common/download.h"

#include <curl/curl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void ensure_curl_global_init(void)
{
    static int initialized = 0;
    if (!initialized) {
        curl_global_init(CURL_GLOBAL_DEFAULT);
        initialized = 1;
    }
}

static struct curl_slist *build_header_list(const bunny_http_header_t *headers, size_t header_count)
{
    struct curl_slist *list = NULL;
    size_t i;
    for (i = 0; i < header_count; i++) {
        const char *name = headers[i].name;
        const char *value = headers[i].value;
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

static size_t write_cb(char *ptr, size_t size, size_t nmemb, void *userdata)
{
    const bunny_download_sink_t *sink = (const bunny_download_sink_t *)userdata;
    size_t len = size * nmemb;
    if (sink->on_chunk(sink->user_data, ptr, len) != 0) {
        return 0; /* signals an error to curl, aborts the transfer */
    }
    return len;
}

static int xferinfo_cb(void *clientp, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal, curl_off_t ulnow)
{
    const bunny_download_sink_t *sink = (const bunny_download_sink_t *)clientp;
    (void)ultotal;
    (void)ulnow;
    if (sink->on_progress) {
        sink->on_progress(sink->user_data, (int64_t)dlnow, dltotal > 0 ? (int64_t)dltotal : -1);
    }
    return 0;
}

bunny_http_result_t bunny_download_fetch(const char *url, const bunny_http_header_t *headers, size_t header_count, const bunny_download_sink_t *sink, long *out_status)
{
    if (!url || !sink || !sink->on_chunk || !out_status) {
        return BUNNY_HTTP_ERR_INVALID_ARG;
    }
    *out_status = 0;

    ensure_curl_global_init();

    CURL *curl = curl_easy_init();
    if (!curl) {
        return BUNNY_HTTP_ERR_NETWORK;
    }

    struct curl_slist *header_list = build_header_list(headers, header_count);

    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, sink);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    /* A whole file, not a quick JSON call -- CURLOPT_TIMEOUT's flat ceiling
     * would unfairly kill a large file on a slow-but-healthy connection.
     * Abort instead if the transfer stalls below ~1 byte/sec for 30s
     * straight, the standard curl idiom for "detect a dead connection,
     * not a slow one." */
    curl_easy_setopt(curl, CURLOPT_LOW_SPEED_LIMIT, 1L);
    curl_easy_setopt(curl, CURLOPT_LOW_SPEED_TIME, 30L);
    curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, xferinfo_cb);
    curl_easy_setopt(curl, CURLOPT_XFERINFODATA, sink);
    if (header_list) {
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, header_list);
    }

    CURLcode res = curl_easy_perform(curl);

    bunny_http_result_t result = BUNNY_HTTP_OK;
    if (res != CURLE_OK) {
        result = BUNNY_HTTP_ERR_NETWORK;
    } else {
        long status = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
        *out_status = status;
    }

    if (header_list) {
        curl_slist_free_all(header_list);
    }
    curl_easy_cleanup(curl);

    return result;
}
