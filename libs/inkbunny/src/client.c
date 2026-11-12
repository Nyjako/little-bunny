#include "inkbunny/client.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "internal.h"

/* Inkbunny signals API-level errors with HTTP 200 + a JSON body containing
 * "error_code"/"error_message" (e.g. bad login, expired/invalid sid), not via
 * HTTP status. HTTP status is only meaningful for transport-level failures
 * (5xx, rate limiting). query_or_null is appended to the URL as "?...",
 * already encoded by the caller. out_json, if non-NULL, receives the parsed
 * response body on INKBUNNY_OK (caller owns it). */
static inkbunny_result_t perform_request(inkbunny_client_t *client, const char *path, const char *query_or_null, cJSON **out_json)
{
    if (!client) {
        return INKBUNNY_ERR_INVALID_ARG;
    }

    bunny_rate_limiter_wait(&client->rate_limiter);

    char url[2048];
    if (query_or_null) {
        snprintf(url, sizeof(url), "%s%s?%s", client->base_url, path, query_or_null);
    } else {
        snprintf(url, sizeof(url), "%s%s", client->base_url, path);
    }

    bunny_http_request_t request;
    memset(&request, 0, sizeof(request));
    request.method = BUNNY_HTTP_GET;
    request.url = url;

    bunny_http_response_t response;
    memset(&response, 0, sizeof(response));
    bunny_http_result_t http_result = bunny_http_send(&client->transport, &request, &response);

    if (http_result != BUNNY_HTTP_OK) {
        bunny_http_response_free(&response);
        return INKBUNNY_ERR_NETWORK;
    }

    if (response.status == 429) {
        bunny_http_response_free(&response);
        return INKBUNNY_ERR_RATE_LIMITED;
    }
    if (response.status >= 500) {
        bunny_http_response_free(&response);
        return INKBUNNY_ERR_SERVER;
    }
    if (response.status < 200 || response.status >= 300) {
        bunny_http_response_free(&response);
        return INKBUNNY_ERR_UNKNOWN;
    }

    if (!response.body || response.body_len == 0) {
        bunny_http_response_free(&response);
        return INKBUNNY_ERR_PARSE;
    }

    cJSON *json = cJSON_ParseWithLength(response.body, response.body_len);
    bunny_http_response_free(&response);
    if (!json) {
        return INKBUNNY_ERR_PARSE;
    }

    if (cJSON_HasObjectItem(json, "error_code")) {
        cJSON_Delete(json);
        /* Every documented/observed error_code (0 = bad login, 2 = invalid
         * sid) is auth/session related; Inkbunny reports "not found" via an
         * empty result set instead of an error_code. */
        return INKBUNNY_ERR_AUTH;
    }

    if (out_json) {
        *out_json = json;
    } else {
        cJSON_Delete(json);
    }
    return INKBUNNY_OK;
}

inkbunny_client_t *inkbunny_client_create(const inkbunny_config_t *config)
{
    inkbunny_client_t *client = calloc(1, sizeof(inkbunny_client_t));
    if (!client) {
        return NULL;
    }

    const char *base_url = (config && config->base_url) ? config->base_url : "https://inkbunny.net";
    client->base_url = goblin_copy_cstr(base_url);
    bunny_rate_limiter_init(&client->rate_limiter, (config && config->min_request_interval_sec > 0) ? config->min_request_interval_sec : 0.5);
    client->transport = (config && config->transport) ? *config->transport : bunny_http_curl_transport();

    if (!client->base_url) {
        inkbunny_client_destroy(client);
        return NULL;
    }

    return client;
}

void inkbunny_client_destroy(inkbunny_client_t *client)
{
    if (!client) {
        return;
    }
    free(client->base_url);
    free(client->sid);
    if (client->website_curl) {
        curl_easy_cleanup(client->website_curl);
    }
    free(client);
}

inkbunny_result_t inkbunny_login(inkbunny_client_t *client, const char *username, const char *password)
{
    if (!client || !username) {
        return INKBUNNY_ERR_INVALID_ARG;
    }

    char *encoded_user = goblin_url_encode(username);
    char *encoded_pass = goblin_url_encode(password ? password : "");
    if (!encoded_user || !encoded_pass) {
        free(encoded_user);
        free(encoded_pass);
        return INKBUNNY_ERR_UNKNOWN;
    }

    char query[700];
    snprintf(query, sizeof(query), "username=%s&password=%s", encoded_user, encoded_pass);
    free(encoded_user);
    free(encoded_pass);

    cJSON *json = NULL;
    inkbunny_result_t result = perform_request(client, "/api_login.php", query, &json);
    if (result != INKBUNNY_OK) {
        return result;
    }

    const char *sid = bunny_json_get_string_or(json, "sid", NULL);
    if (!sid) {
        cJSON_Delete(json);
        return INKBUNNY_ERR_PARSE;
    }

    char *sid_copy = goblin_copy_cstr(sid);
    if (!sid_copy) {
        cJSON_Delete(json);
        return INKBUNNY_ERR_UNKNOWN;
    }

    free(client->sid);
    client->sid = sid_copy;
    client->user_id = inkbunny_field_int64(json, "user_id", 0);

    cJSON_Delete(json);
    return INKBUNNY_OK;
}

inkbunny_result_t inkbunny_logout(inkbunny_client_t *client)
{
    if (!client) {
        return INKBUNNY_ERR_INVALID_ARG;
    }
    if (!client->sid) {
        return INKBUNNY_OK;
    }

    char query[128];
    snprintf(query, sizeof(query), "sid=%s", client->sid);

    inkbunny_result_t result = perform_request(client, "/api_logout.php", query, NULL);

    free(client->sid);
    client->sid = NULL;
    client->user_id = 0;

    return result;
}

int64_t inkbunny_client_get_user_id(const inkbunny_client_t *client)
{
    return client ? client->user_id : 0;
}

/* Comma-separated submission_type_id list from a INKBUNNY_SUBMISSION_TYPE_BIT
 * mask (api_search.php's own `type` param format: "no spaces"). out must be
 * at least 42 bytes (14 two-digit ids + 13 commas + NUL). Returns the number
 * of ids written, 0 if mask is 0 (caller should then omit the param entirely). */
static int inkbunny_submission_type_mask_to_list(unsigned mask, char *out, size_t out_size)
{
    size_t offset = 0;
    int count = 0;
    for (int type_id = 1; type_id <= 14; type_id++) {
        if (!(mask & INKBUNNY_SUBMISSION_TYPE_BIT(type_id))) {
            continue;
        }
        offset += (size_t)snprintf(out + offset, out_size - offset, "%s%d", count > 0 ? "," : "", type_id);
        count++;
    }
    return count;
}

static const char *inkbunny_field_join_str(inkbunny_field_join_t join)
{
    return join == INKBUNNY_FIELD_JOIN_AND ? "and" : "or";
}

static const char *inkbunny_string_join_str(inkbunny_string_join_t join)
{
    switch (join) {
        case INKBUNNY_STRING_JOIN_OR:
            return "or";
        case INKBUNNY_STRING_JOIN_EXACT:
            return "exact";
        case INKBUNNY_STRING_JOIN_AND:
        default:
            return "and";
    }
}

static const char *inkbunny_scraps_str(inkbunny_scraps_t scraps)
{
    switch (scraps) {
        case INKBUNNY_SCRAPS_NO:
            return "no";
        case INKBUNNY_SCRAPS_ONLY:
            return "only";
        case INKBUNNY_SCRAPS_BOTH:
        default:
            return "both";
    }
}

inkbunny_result_t inkbunny_search(inkbunny_client_t *client, const inkbunny_search_params_t *params, inkbunny_submission_list_t *out_submissions)
{
    if (!client || !out_submissions) {
        return INKBUNNY_ERR_INVALID_ARG;
    }
    if (!client->sid) {
        return INKBUNNY_ERR_AUTH;
    }

    char query[2048];
    int written = snprintf(query, sizeof(query), "sid=%s", client->sid);
    size_t offset = (size_t)written;

    if (params) {
        if (params->text && params->text[0]) {
            char *encoded_text = goblin_url_encode(params->text);
            if (!encoded_text) {
                return INKBUNNY_ERR_UNKNOWN;
            }
            offset += (size_t)snprintf(query + offset, sizeof(query) - offset, "&text=%s", encoded_text);
            free(encoded_text);

            int mask = params->search_in_mask ? params->search_in_mask : INKBUNNY_SEARCH_IN_KEYWORDS;
            offset += (size_t)snprintf(query + offset, sizeof(query) - offset, "&keywords=%s", (mask & INKBUNNY_SEARCH_IN_KEYWORDS) ? "yes" : "no");
            offset += (size_t)snprintf(query + offset, sizeof(query) - offset, "&title=%s", (mask & INKBUNNY_SEARCH_IN_TITLE) ? "yes" : "no");
            offset += (size_t)snprintf(query + offset, sizeof(query) - offset, "&description=%s", (mask & INKBUNNY_SEARCH_IN_DESCRIPTION) ? "yes" : "no");
            offset += (size_t)snprintf(query + offset, sizeof(query) - offset, "&md5=%s", (mask & INKBUNNY_SEARCH_IN_MD5) ? "yes" : "no");
            offset += (size_t)snprintf(query + offset, sizeof(query) - offset, "&field_join_type=%s", inkbunny_field_join_str(params->field_join));
            offset += (size_t)snprintf(query + offset, sizeof(query) - offset, "&string_join_type=%s", inkbunny_string_join_str(params->string_join));
        }
        if (params->favorited_by_user_id && params->favorited_by_user_id[0]) {
            offset += (size_t)snprintf(query + offset, sizeof(query) - offset, "&favs_user_id=%s", params->favorited_by_user_id);
        }
        if (params->username && params->username[0]) {
            char *encoded_username = goblin_url_encode(params->username);
            if (!encoded_username) {
                return INKBUNNY_ERR_UNKNOWN;
            }
            offset += (size_t)snprintf(query + offset, sizeof(query) - offset, "&username=%s", encoded_username);
            free(encoded_username);
        }
        if (params->pool_id > 0) {
            offset += (size_t)snprintf(query + offset, sizeof(query) - offset, "&pool_id=%lld", (long long)params->pool_id);
        }
        if (params->submission_type_mask) {
            char type_list[42];
            inkbunny_submission_type_mask_to_list(params->submission_type_mask, type_list, sizeof(type_list));
            offset += (size_t)snprintf(query + offset, sizeof(query) - offset, "&type=%s", type_list);
        }
        if (params->days_limit > 0) {
            offset += (size_t)snprintf(query + offset, sizeof(query) - offset, "&dayslimit=%d", params->days_limit);
        }
        if (params->order_by && params->order_by[0]) {
            offset += (size_t)snprintf(query + offset, sizeof(query) - offset, "&orderby=%s", params->order_by);
        }
        if (params->random) {
            offset += (size_t)snprintf(query + offset, sizeof(query) - offset, "&random=yes");
        }
        if (params->scraps != INKBUNNY_SCRAPS_BOTH) {
            offset += (size_t)snprintf(query + offset, sizeof(query) - offset, "&scraps=%s", inkbunny_scraps_str(params->scraps));
        }
        if (params->page > 0) {
            offset += (size_t)snprintf(query + offset, sizeof(query) - offset, "&page=%d", params->page);
        }
    }

    cJSON *json = NULL;
    inkbunny_result_t result = perform_request(client, "/api_search.php", query, &json);
    if (result != INKBUNNY_OK) {
        return result;
    }

    cJSON *submissions_array = cJSON_GetObjectItemCaseSensitive(json, "submissions");
    if (!submissions_array || !cJSON_IsArray(submissions_array)) {
        cJSON_Delete(json);
        return INKBUNNY_ERR_PARSE;
    }

    result = inkbunny_parse_submission_array(submissions_array, out_submissions);
    cJSON_Delete(json);
    return result;
}

inkbunny_result_t inkbunny_get_submissions(inkbunny_client_t *client, const int64_t *submission_ids, size_t submission_id_count, inkbunny_submission_list_t *out_submissions)
{
    if (!client || !out_submissions || !submission_ids || submission_id_count == 0) {
        return INKBUNNY_ERR_INVALID_ARG;
    }
    if (submission_id_count > 100) {
        return INKBUNNY_ERR_INVALID_ARG;
    }
    if (!client->sid) {
        return INKBUNNY_ERR_AUTH;
    }

    char ids_buf[1400];
    size_t offset = 0;
    for (size_t i = 0; i < submission_id_count; i++) {
        int written = snprintf(ids_buf + offset, sizeof(ids_buf) - offset, "%s%lld", i == 0 ? "" : ",", (long long)submission_ids[i]);
        if (written < 0 || (size_t)written >= sizeof(ids_buf) - offset) {
            return INKBUNNY_ERR_INVALID_ARG;
        }
        offset += (size_t)written;
    }

    char query[1700];
    snprintf(query, sizeof(query), "sid=%s&submission_ids=%s&show_description=yes&show_pools=yes", client->sid, ids_buf);

    cJSON *json = NULL;
    inkbunny_result_t result = perform_request(client, "/api_submissions.php", query, &json);
    if (result != INKBUNNY_OK) {
        return result;
    }

    cJSON *submissions_array = cJSON_GetObjectItemCaseSensitive(json, "submissions");
    if (!submissions_array || !cJSON_IsArray(submissions_array)) {
        cJSON_Delete(json);
        return INKBUNNY_ERR_PARSE;
    }

    result = inkbunny_parse_submission_array(submissions_array, out_submissions);
    cJSON_Delete(json);
    return result;
}

inkbunny_result_t inkbunny_get_submission(inkbunny_client_t *client, int64_t submission_id, inkbunny_submission_t *out_submission)
{
    if (!client || !out_submission) {
        return INKBUNNY_ERR_INVALID_ARG;
    }

    inkbunny_submission_list_t list;
    memset(&list, 0, sizeof(list));
    inkbunny_result_t result = inkbunny_get_submissions(client, &submission_id, 1, &list);
    if (result != INKBUNNY_OK) {
        return result;
    }

    if (list.count == 0) {
        inkbunny_submission_list_free(&list);
        return INKBUNNY_ERR_NOT_FOUND;
    }

    *out_submission = list.items[0];
    /* move the first item out of the list without freeing its contents */
    memset(&list.items[0], 0, sizeof(list.items[0]));
    inkbunny_submission_list_free(&list);
    return INKBUNNY_OK;
}
