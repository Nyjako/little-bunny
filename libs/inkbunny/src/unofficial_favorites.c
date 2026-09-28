#include "inkbunny/unofficial_favorites.h"

#include <cJSON.h>
#include <curl/curl.h>

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "internal.h"

typedef struct {
    char *data;
    size_t len;
} buffer_t;

static size_t write_cb(char *ptr, size_t size, size_t nmemb, void *userdata) {
    buffer_t *buf = (buffer_t *)userdata;
    size_t add = size * nmemb;
    char *new_data = realloc(buf->data, buf->len + add + 1);
    if (!new_data) {
        return 0;
    }
    buf->data = new_data;
    memcpy(buf->data + buf->len, ptr, add);
    buf->len += add;
    buf->data[buf->len] = '\0';
    return add;
}

static void buffer_free(buffer_t *buf) {
    free(buf->data);
    buf->data = NULL;
    buf->len = 0;
}

/* Finds `anchor` verbatim (e.g. name="token", or just general-global_token
 * without assuming which attribute holds it), then returns a copy of the
 * nearest value=... within the same tag. Quote-agnostic: Inkbunny mixes
 * single- and double-quoted attributes across its own pages (confirmed
 * live - login.php's CSRF token is double-quoted, the submission page's
 * global_token input is single-quoted), so this matches whichever quote
 * character actually follows "value=". Returns NULL if not found. */
static char *extract_input_value(const char *html, const char *anchor) {
    const char *match = strstr(html, anchor);
    if (!match) {
        return NULL;
    }

    const char *tag_start = match;
    while (tag_start > html && *tag_start != '<') {
        tag_start--;
    }
    const char *tag_end = strchr(match, '>');
    if (!tag_end) {
        return NULL;
    }

    const char *value_marker = "value=";
    size_t marker_len = strlen(value_marker);
    const char *value_pos = NULL;
    for (const char *p = tag_start; p + marker_len < tag_end; p++) {
        if (strncmp(p, value_marker, marker_len) == 0) {
            value_pos = p + marker_len;
            break;
        }
    }
    if (!value_pos || value_pos >= tag_end) {
        return NULL;
    }

    char quote = *value_pos;
    if (quote != '"' && quote != '\'') {
        return NULL;
    }
    value_pos++;

    const char *end = strchr(value_pos, quote);
    if (!end || end > tag_end) {
        return NULL;
    }

    size_t len = (size_t)(end - value_pos);
    char *result = malloc(len + 1);
    if (!result) {
        return NULL;
    }
    memcpy(result, value_pos, len);
    result[len] = '\0';
    return result;
}

static bool http_get(CURL *curl, const char *url, buffer_t *out) {
    memset(out, 0, sizeof(*out));
    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_HTTPGET, 1L);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, out);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, NULL);
    return curl_easy_perform(curl) == CURLE_OK;
}

static bool http_post_form(CURL *curl, const char *url, const char *body, bool want_json_header,
                            buffer_t *out) {
    memset(out, 0, sizeof(*out));
    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, out);

    struct curl_slist *headers = NULL;
    if (want_json_header) {
        headers = curl_slist_append(headers, "Accept: application/json");
    }
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

    CURLcode res = curl_easy_perform(curl);
    curl_slist_free_all(headers);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, NULL);
    return res == CURLE_OK;
}

static CURL *ensure_website_curl(inkbunny_client_t *client) {
    if (!client->website_curl) {
        client->website_curl = curl_easy_init();
        if (client->website_curl) {
            curl_easy_setopt(client->website_curl, CURLOPT_COOKIEFILE, ""); /* in-memory cookie engine */
            curl_easy_setopt(client->website_curl, CURLOPT_USERAGENT, "LittleBunny/0.1 (unofficial-favorites)");
            curl_easy_setopt(client->website_curl, CURLOPT_FOLLOWLOCATION, 1L);
            curl_easy_setopt(client->website_curl, CURLOPT_TIMEOUT, 30L);
        }
    }
    return client->website_curl;
}

inkbunny_result_t inkbunny_website_login(inkbunny_client_t *client, const char *username, const char *password) {
    if (!client || !username || !password) {
        return INKBUNNY_ERR_INVALID_ARG;
    }

    CURL *curl = ensure_website_curl(client);
    if (!curl) {
        return INKBUNNY_ERR_UNKNOWN;
    }

    buffer_t page = {0};
    inkbunny_result_t result = INKBUNNY_ERR_UNKNOWN;
    char *login_token = NULL;
    char *encoded_user = NULL;
    char *encoded_pass = NULL;
    char *encoded_login_token = NULL;
    char *login_body = NULL;

    if (!http_get(curl, "https://inkbunny.net/login.php", &page)) {
        result = INKBUNNY_ERR_NETWORK;
        goto cleanup;
    }
    login_token = extract_input_value(page.data, "name=\"token\"");
    if (!login_token) {
        result = INKBUNNY_ERR_PARSE;
        goto cleanup;
    }
    buffer_free(&page);

    encoded_user = inkbunny_url_encode(username);
    encoded_pass = inkbunny_url_encode(password);
    encoded_login_token = inkbunny_url_encode(login_token);
    if (!encoded_user || !encoded_pass || !encoded_login_token) {
        result = INKBUNNY_ERR_UNKNOWN;
        goto cleanup;
    }

    {
        size_t needed = strlen("token=&username=&password=") + strlen(encoded_login_token) +
                         strlen(encoded_user) + strlen(encoded_pass) + 1;
        login_body = malloc(needed);
        if (!login_body) {
            result = INKBUNNY_ERR_UNKNOWN;
            goto cleanup;
        }
        snprintf(login_body, needed, "token=%s&username=%s&password=%s", encoded_login_token, encoded_user,
                 encoded_pass);
    }

    if (!http_post_form(curl, "https://inkbunny.net/login_process.php", login_body, false, &page)) {
        result = INKBUNNY_ERR_NETWORK;
        goto cleanup;
    }

    {
        char *final_url = NULL;
        curl_easy_getinfo(curl, CURLINFO_EFFECTIVE_URL, &final_url);
        if (final_url && strstr(final_url, "/login.php")) {
            result = INKBUNNY_ERR_AUTH;
            goto cleanup;
        }
    }

    result = INKBUNNY_OK;

cleanup:
    buffer_free(&page);
    free(login_token);
    free(encoded_user);
    free(encoded_pass);
    free(encoded_login_token);
    free(login_body);
    return result;
}

static inkbunny_result_t favorite_process(inkbunny_client_t *client, int64_t submission_id, bool is_add,
                                           int stars) {
    if (!client) {
        return INKBUNNY_ERR_INVALID_ARG;
    }
    if (!client->website_curl) {
        return INKBUNNY_ERR_AUTH;
    }
    CURL *curl = client->website_curl;

    buffer_t page = {0};
    inkbunny_result_t result = INKBUNNY_ERR_UNKNOWN;
    char *global_token = NULL;
    char *encoded_global_token = NULL;
    char *fav_body = NULL;

    char submission_url[256];
    snprintf(submission_url, sizeof(submission_url), "https://inkbunny.net/s/%lld", (long long)submission_id);
    if (!http_get(curl, submission_url, &page)) {
        result = INKBUNNY_ERR_NETWORK;
        goto cleanup;
    }

    global_token = extract_input_value(page.data, "general-global_token");
    if (!global_token) {
        result = INKBUNNY_ERR_PARSE;
        goto cleanup;
    }
    buffer_free(&page);

    encoded_global_token = inkbunny_url_encode(global_token);
    if (!encoded_global_token) {
        result = INKBUNNY_ERR_UNKNOWN;
        goto cleanup;
    }

    {
        char stars_str[4];
        snprintf(stars_str, sizeof(stars_str), "%d", is_add ? stars : 0);
        size_t needed = strlen("token=&stars=&add=false&remove=false&submission_id=") +
                         strlen(encoded_global_token) + strlen(stars_str) + 32;
        fav_body = malloc(needed);
        if (!fav_body) {
            result = INKBUNNY_ERR_UNKNOWN;
            goto cleanup;
        }
        snprintf(fav_body, needed, "token=%s&stars=%s&add=%s&remove=%s&submission_id=%lld", encoded_global_token,
                 stars_str, is_add ? "true" : "false", is_add ? "false" : "true", (long long)submission_id);
    }

    if (!http_post_form(curl, "https://inkbunny.net/submissionfav_process.php", fav_body, true, &page)) {
        result = INKBUNNY_ERR_NETWORK;
        goto cleanup;
    }

    {
        /* Prototype.js wraps successful JSON responses as "/*-secure-\n{...}\n*\/"
         * (an old defense against JSON-hijacking); strip that before parsing. */
        const char *json_start = strchr(page.data, '{');
        const char *json_end = strrchr(page.data, '}');
        if (!json_start || !json_end || json_end < json_start) {
            result = INKBUNNY_ERR_PARSE;
            goto cleanup;
        }
        size_t json_len = (size_t)(json_end - json_start) + 1;
        char *json_only = malloc(json_len + 1);
        if (!json_only) {
            result = INKBUNNY_ERR_UNKNOWN;
            goto cleanup;
        }
        memcpy(json_only, json_start, json_len);
        json_only[json_len] = '\0';

        cJSON *parsed = cJSON_Parse(json_only);
        free(json_only);
        if (!parsed) {
            result = INKBUNNY_ERR_PARSE;
            goto cleanup;
        }
        cJSON *success = cJSON_GetObjectItemCaseSensitive(parsed, "success");
        result =
            (cJSON_IsString(success) && strcmp(success->valuestring, "yes") == 0) ? INKBUNNY_OK : INKBUNNY_ERR_UNKNOWN;
        cJSON_Delete(parsed);
    }

cleanup:
    buffer_free(&page);
    free(global_token);
    free(encoded_global_token);
    free(fav_body);
    return result;
}

inkbunny_result_t inkbunny_favorite_add(inkbunny_client_t *client, int64_t submission_id, int stars) {
    if (stars != 1 && stars != 2 && stars != 3) {
        return INKBUNNY_ERR_INVALID_ARG;
    }
    return favorite_process(client, submission_id, true, stars);
}

inkbunny_result_t inkbunny_favorite_remove(inkbunny_client_t *client, int64_t submission_id) {
    return favorite_process(client, submission_id, false, 0);
}
