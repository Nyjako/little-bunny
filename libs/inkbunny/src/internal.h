#ifndef INKBUNNY_INTERNAL_H
#define INKBUNNY_INTERNAL_H

#include <bunny_common/http.h>
#include <bunny_common/json.h>
#include <ctype.h>
#include <curl/curl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "inkbunny/error.h"
#include "inkbunny/types.h"

/* Shared between client.c (owns lifecycle + the official API calls) and
 * unofficial_favorites.c (uses website_curl for the website-session-based
 * favorite/unfavorite flow -- see inkbunny/unofficial_favorites.h). */
struct inkbunny_client
{
    char *base_url;
    char *sid;
    int64_t user_id;
    double min_request_interval_sec;
    bunny_http_transport_t transport;
    struct timespec last_request_time;
    bool has_last_request_time;

    /* NULL until inkbunny_website_login() succeeds. Kept alive for the
     * client's lifetime so its cookie jar persists across favorite/unfavorite
     * calls; not related to `sid`, which is the official API's session. */
    CURL *website_curl;
};

/* JSON <-> struct (de)serialization, shared between client.c and tests. */
inkbunny_result_t inkbunny_parse_submission(const cJSON *json, inkbunny_submission_t *out);
inkbunny_result_t inkbunny_parse_submission_array(const cJSON *json_array, inkbunny_submission_list_t *out);

/*
 * Inkbunny encodes every numeric field as a JSON string (e.g. "submission_id": "12345"),
 * and every boolean as the string "t" or "f", confirmed against the live API. These
 * helpers tolerate a real JSON number/bool too, in case that ever changes.
 */
static inline int64_t inkbunny_field_int64(const cJSON *object, const char *key, int64_t default_value)
{
    if (!object || !cJSON_IsObject(object)) {
        return default_value;
    }
    cJSON *field = cJSON_GetObjectItemCaseSensitive(object, key);
    if (!field) {
        return default_value;
    }
    if (cJSON_IsNumber(field)) {
        return (int64_t)field->valuedouble;
    }
    if (cJSON_IsString(field) && field->valuestring) {
        return strtoll(field->valuestring, NULL, 10);
    }
    return default_value;
}

static inline int inkbunny_field_int(const cJSON *object, const char *key, int default_value)
{
    return (int)inkbunny_field_int64(object, key, default_value);
}

static inline bool inkbunny_field_bool_tf(const cJSON *object, const char *key, bool default_value)
{
    const char *value = bunny_json_get_string_or(object, key, NULL);
    if (!value) {
        return default_value;
    }
    if (strcmp(value, "t") == 0) {
        return true;
    }
    if (strcmp(value, "f") == 0) {
        return false;
    }
    return default_value;
}

/* Shared between client.c (official API query strings) and
 * unofficial_favorites.c (website form bodies). */
static inline char *inkbunny_url_encode(const char *value)
{
    if (!value) {
        return strdup("");
    }
    size_t len = strlen(value);
    char *out = malloc(len * 3 + 1);
    if (!out) {
        return NULL;
    }
    size_t j = 0;
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)value[i];
        if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
            out[j++] = (char)c;
        } else {
            snprintf(out + j, 4, "%%%02X", c);
            j += 3;
        }
    }
    out[j] = '\0';
    return out;
}

#endif /* INKBUNNY_INTERNAL_H */
