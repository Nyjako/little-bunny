#include "e621/client.h"

#include <goblin/cstr.h>

#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "internal.h"

struct e621_client
{
    char *base_url;
    char *user_agent;
    char *username;
    char *api_key;
    double min_request_interval_sec;
    bunny_http_transport_t transport;
    struct timespec last_request_time;
    bool has_last_request_time;
};

static char *url_encode(const char *value)
{
    if (!value) {
        return goblin_copy_cstr("");
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

static char *base64_encode(const unsigned char *data, size_t len)
{
    static const char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t out_len = 4 * ((len + 2) / 3);
    char *out = malloc(out_len + 1);
    if (!out) {
        return NULL;
    }

    size_t i = 0, j = 0;
    while (i < len) {
        uint32_t octet_a = i < len ? (unsigned char)data[i++] : 0;
        uint32_t octet_b = i < len ? (unsigned char)data[i++] : 0;
        uint32_t octet_c = i < len ? (unsigned char)data[i++] : 0;
        uint32_t triple = (octet_a << 16) + (octet_b << 8) + octet_c;

        out[j++] = table[(triple >> 18) & 0x3F];
        out[j++] = table[(triple >> 12) & 0x3F];
        out[j++] = table[(triple >> 6) & 0x3F];
        out[j++] = table[triple & 0x3F];
    }

    size_t mod = len % 3;
    if (mod == 1) {
        out[out_len - 1] = '=';
        out[out_len - 2] = '=';
    } else if (mod == 2) {
        out[out_len - 1] = '=';
    }
    out[out_len] = '\0';
    return out;
}

static char *build_basic_auth_header(const char *username, const char *api_key)
{
    size_t combined_len = strlen(username) + 1 + strlen(api_key);
    char *combined = malloc(combined_len + 1);
    if (!combined) {
        return NULL;
    }
    snprintf(combined, combined_len + 1, "%s:%s", username, api_key);

    char *encoded = base64_encode((unsigned char *)combined, combined_len);
    free(combined);
    if (!encoded) {
        return NULL;
    }

    size_t header_len = strlen("Basic ") + strlen(encoded) + 1;
    char *header = malloc(header_len);
    if (header) {
        snprintf(header, header_len, "Basic %s", encoded);
    }
    free(encoded);
    return header;
}

static void rate_limit_wait(e621_client_t *client)
{
    if (client->min_request_interval_sec <= 0) {
        return;
    }

    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);

    if (client->has_last_request_time) {
        double elapsed = (double)(now.tv_sec - client->last_request_time.tv_sec) + (double)(now.tv_nsec - client->last_request_time.tv_nsec) / 1e9;
        double remaining = client->min_request_interval_sec - elapsed;
        if (remaining > 0) {
            struct timespec sleep_time;
            sleep_time.tv_sec = (time_t)remaining;
            sleep_time.tv_nsec = (long)((remaining - (double)sleep_time.tv_sec) * 1e9);
            nanosleep(&sleep_time, NULL);
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &client->last_request_time);
    client->has_last_request_time = true;
}

static e621_result_t status_to_result(long status)
{
    if (status >= 200 && status < 300) {
        return E621_OK;
    }
    if (status == 401 || status == 403) {
        return E621_ERR_AUTH;
    }
    if (status == 404) {
        return E621_ERR_NOT_FOUND;
    }
    if (status == 429) {
        return E621_ERR_RATE_LIMITED;
    }
    if (status >= 500) {
        return E621_ERR_SERVER;
    }
    return E621_ERR_UNKNOWN;
}

/* query_or_null is appended to the URL as "?...", already encoded by the caller.
 * body_or_null, if present, is sent as a application/x-www-form-urlencoded body.
 * out_json, if non-NULL, receives the parsed response body on E621_OK (caller owns it). */
static e621_result_t perform_request(e621_client_t *client, bunny_http_method_t method, const char *path, const char *query_or_null, const char *body_or_null, cJSON **out_json)
{
    if (!client) {
        return E621_ERR_INVALID_ARG;
    }

    rate_limit_wait(client);

    char url[2048];
    if (query_or_null) {
        snprintf(url, sizeof(url), "%s%s?%s", client->base_url, path, query_or_null);
    } else {
        snprintf(url, sizeof(url), "%s%s", client->base_url, path);
    }

    bunny_http_header_t headers[3];
    size_t header_count = 0;

    headers[header_count].name = "User-Agent";
    headers[header_count].value = client->user_agent;
    header_count++;

    char *auth_header = NULL;
    if (client->username && client->api_key) {
        auth_header = build_basic_auth_header(client->username, client->api_key);
        if (auth_header) {
            headers[header_count].name = "Authorization";
            headers[header_count].value = auth_header;
            header_count++;
        }
    }

    if (body_or_null) {
        headers[header_count].name = "Content-Type";
        headers[header_count].value = "application/x-www-form-urlencoded";
        header_count++;
    }

    bunny_http_request_t request;
    memset(&request, 0, sizeof(request));
    request.method = method;
    request.url = url;
    request.headers = headers;
    request.header_count = header_count;
    request.body = body_or_null;
    request.body_len = body_or_null ? strlen(body_or_null) : 0;

    bunny_http_response_t response;
    memset(&response, 0, sizeof(response));
    bunny_http_result_t http_result = bunny_http_send(&client->transport, &request, &response);

    free(auth_header);

    if (http_result != BUNNY_HTTP_OK) {
        bunny_http_response_free(&response);
        return E621_ERR_NETWORK;
    }

    e621_result_t result = status_to_result(response.status);

    if (out_json) {
        *out_json = NULL;
        if (result == E621_OK && response.body && response.body_len > 0) {
            cJSON *parsed = cJSON_ParseWithLength(response.body, response.body_len);
            if (!parsed) {
                bunny_http_response_free(&response);
                return E621_ERR_PARSE;
            }
            *out_json = parsed;
        }
    }

    bunny_http_response_free(&response);
    return result;
}

e621_client_t *e621_client_create(const e621_config_t *config)
{
    if (!config || !config->user_agent) {
        return NULL;
    }

    e621_client_t *client = calloc(1, sizeof(e621_client_t));
    if (!client) {
        return NULL;
    }

    const char *base_url = config->base_url ? config->base_url : "https://e621.net";
    client->base_url = goblin_copy_cstr(base_url);
    client->user_agent = goblin_copy_cstr(config->user_agent);
    client->username = config->username ? goblin_copy_cstr(config->username) : NULL;
    client->api_key = config->api_key ? goblin_copy_cstr(config->api_key) : NULL;
    client->min_request_interval_sec = config->min_request_interval_sec > 0 ? config->min_request_interval_sec : 0.5;
    client->transport = config->transport ? *config->transport : bunny_http_curl_transport();
    client->has_last_request_time = false;

    if (!client->base_url || !client->user_agent) {
        e621_client_destroy(client);
        return NULL;
    }

    return client;
}

void e621_client_destroy(e621_client_t *client)
{
    if (!client) {
        return;
    }
    free(client->base_url);
    free(client->user_agent);
    free(client->username);
    free(client->api_key);
    free(client);
}

/* Shared by e621_search_posts/_after/_before -- `page_param` is the exact
 * value of the `page=` query param (e.g. "1", "a42", "b42"). */
static e621_result_t search_posts_with_page_param(e621_client_t *client, const char *tags, const char *page_param, int limit, e621_post_list_t *out_posts)
{
    if (!client || !out_posts) {
        return E621_ERR_INVALID_ARG;
    }

    char *encoded_tags = url_encode(tags ? tags : "");
    if (!encoded_tags) {
        return E621_ERR_UNKNOWN;
    }

    char query[1600];
    snprintf(query, sizeof(query), "tags=%s&page=%s&limit=%d", encoded_tags, page_param, limit > 0 ? limit : 75);
    free(encoded_tags);

    cJSON *json = NULL;
    e621_result_t result = perform_request(client, BUNNY_HTTP_GET, "/posts.json", query, NULL, &json);
    if (result != E621_OK) {
        return result;
    }

    cJSON *posts_array = cJSON_GetObjectItemCaseSensitive(json, "posts");
    if (!posts_array || !cJSON_IsArray(posts_array)) {
        cJSON_Delete(json);
        return E621_ERR_PARSE;
    }

    result = e621_parse_post_array(posts_array, out_posts);
    cJSON_Delete(json);
    return result;
}

e621_result_t e621_search_posts(e621_client_t *client, const char *tags, int page, int limit, e621_post_list_t *out_posts)
{
    char page_param[16];
    snprintf(page_param, sizeof(page_param), "%d", page > 0 ? page : 1);
    return search_posts_with_page_param(client, tags, page_param, limit, out_posts);
}

e621_result_t e621_search_posts_after(e621_client_t *client, const char *tags, int64_t after_post_id, int limit, e621_post_list_t *out_posts)
{
    char page_param[32];
    snprintf(page_param, sizeof(page_param), "a%lld", (long long)after_post_id);
    return search_posts_with_page_param(client, tags, page_param, limit, out_posts);
}

e621_result_t e621_search_posts_before(e621_client_t *client, const char *tags, int64_t before_post_id, int limit, e621_post_list_t *out_posts)
{
    char page_param[32];
    snprintf(page_param, sizeof(page_param), "b%lld", (long long)before_post_id);
    return search_posts_with_page_param(client, tags, page_param, limit, out_posts);
}

e621_result_t e621_get_post(e621_client_t *client, int64_t post_id, e621_post_t *out_post)
{
    if (!client || !out_post) {
        return E621_ERR_INVALID_ARG;
    }

    char path[128];
    snprintf(path, sizeof(path), "/posts/%lld.json", (long long)post_id);

    cJSON *json = NULL;
    e621_result_t result = perform_request(client, BUNNY_HTTP_GET, path, NULL, NULL, &json);
    if (result != E621_OK) {
        return result;
    }

    cJSON *post_obj = cJSON_GetObjectItemCaseSensitive(json, "post");
    if (!post_obj) {
        cJSON_Delete(json);
        return E621_ERR_PARSE;
    }

    result = e621_parse_post(post_obj, out_post);
    cJSON_Delete(json);
    return result;
}

e621_result_t e621_favorite_add(e621_client_t *client, int64_t post_id)
{
    if (!client) {
        return E621_ERR_INVALID_ARG;
    }
    if (!client->username || !client->api_key) {
        return E621_ERR_AUTH;
    }

    char body[64];
    snprintf(body, sizeof(body), "post_id=%lld", (long long)post_id);

    return perform_request(client, BUNNY_HTTP_POST, "/favorites.json", NULL, body, NULL);
}

e621_result_t e621_favorite_remove(e621_client_t *client, int64_t post_id)
{
    if (!client) {
        return E621_ERR_INVALID_ARG;
    }
    if (!client->username || !client->api_key) {
        return E621_ERR_AUTH;
    }

    char path[128];
    snprintf(path, sizeof(path), "/favorites/%lld.json", (long long)post_id);

    return perform_request(client, BUNNY_HTTP_DELETE, path, NULL, NULL, NULL);
}

e621_result_t e621_vote(e621_client_t *client, int64_t post_id, int score, bool no_unvote)
{
    if (!client) {
        return E621_ERR_INVALID_ARG;
    }
    if (score != 1 && score != -1) {
        return E621_ERR_INVALID_ARG;
    }
    if (!client->username || !client->api_key) {
        return E621_ERR_AUTH;
    }

    char path[128];
    snprintf(path, sizeof(path), "/posts/%lld/votes.json", (long long)post_id);

    char body[64];
    snprintf(body, sizeof(body), "score=%d&no_unvote=%s", score, no_unvote ? "true" : "false");

    return perform_request(client, BUNNY_HTTP_POST, path, NULL, body, NULL);
}

e621_result_t e621_list_favorites(e621_client_t *client, const char *user_id, int page, e621_post_list_t *out_posts)
{
    if (!client || !out_posts) {
        return E621_ERR_INVALID_ARG;
    }

    char query[256];
    if (user_id) {
        snprintf(query, sizeof(query), "user_id=%s&page=%d", user_id, page > 0 ? page : 1);
    } else {
        snprintf(query, sizeof(query), "page=%d", page > 0 ? page : 1);
    }

    cJSON *json = NULL;
    e621_result_t result = perform_request(client, BUNNY_HTTP_GET, "/favorites.json", query, NULL, &json);
    if (result != E621_OK) {
        return result;
    }

    cJSON *posts_array = cJSON_GetObjectItemCaseSensitive(json, "posts");
    if (!posts_array || !cJSON_IsArray(posts_array)) {
        cJSON_Delete(json);
        return E621_ERR_PARSE;
    }

    result = e621_parse_post_array(posts_array, out_posts);
    cJSON_Delete(json);
    return result;
}

e621_result_t e621_comment_create(e621_client_t *client, int64_t post_id, const char *body, bool anonymous, e621_comment_t *out_comment)
{
    if (!client || !body) {
        return E621_ERR_INVALID_ARG;
    }
    if (!anonymous && (!client->username || !client->api_key)) {
        return E621_ERR_AUTH;
    }

    char *encoded_body = url_encode(body);
    if (!encoded_body) {
        return E621_ERR_UNKNOWN;
    }

    size_t needed = strlen("comment[post_id]=&comment[body]=&comment[anonymous]=false") + 24 + strlen(encoded_body) + 1;
    char *form_body = malloc(needed);
    if (!form_body) {
        free(encoded_body);
        return E621_ERR_UNKNOWN;
    }
    snprintf(form_body, needed, "comment[post_id]=%lld&comment[body]=%s&comment[anonymous]=%s", (long long)post_id, encoded_body, anonymous ? "true" : "false");
    free(encoded_body);

    cJSON *json = NULL;
    e621_result_t result = perform_request(client, BUNNY_HTTP_POST, "/comments.json", NULL, form_body, out_comment ? &json : NULL);
    free(form_body);
    if (result != E621_OK) {
        return result;
    }

    if (out_comment) {
        if (!json) {
            return E621_ERR_PARSE;
        }
        result = e621_parse_comment(json, out_comment);
        cJSON_Delete(json);
    }

    return result;
}

e621_result_t e621_comment_list(e621_client_t *client, int64_t post_id, e621_comment_list_t *out_comments)
{
    if (!client || !out_comments) {
        return E621_ERR_INVALID_ARG;
    }

    char query[64];
    snprintf(query, sizeof(query), "search[post_id]=%lld", (long long)post_id);

    cJSON *json = NULL;
    e621_result_t result = perform_request(client, BUNNY_HTTP_GET, "/comments.json", query, NULL, &json);
    if (result != E621_OK) {
        return result;
    }

    if (!cJSON_IsArray(json)) {
        cJSON_Delete(json);
        return E621_ERR_PARSE;
    }

    result = e621_parse_comment_array(json, out_comments);
    cJSON_Delete(json);
    return result;
}

e621_result_t e621_get_pool(e621_client_t *client, int64_t pool_id, e621_pool_t *out_pool)
{
    if (!client || !out_pool) {
        return E621_ERR_INVALID_ARG;
    }

    char path[128];
    snprintf(path, sizeof(path), "/pools/%lld.json", (long long)pool_id);

    cJSON *json = NULL;
    e621_result_t result = perform_request(client, BUNNY_HTTP_GET, path, NULL, NULL, &json);
    if (result != E621_OK) {
        return result;
    }

    /* unlike /posts/{id}.json, the pool object is returned directly, not wrapped in {"pool": ...} */
    result = e621_parse_pool(json, out_pool);
    cJSON_Delete(json);
    return result;
}
