#include "routes_searches.h"

#include <bunny_common/json.h>
#include <bunny_core/core.h>
#include <cJSON.h>

#include <stdbool.h>
#include <string.h>

#include "auth.h"
#include "json_helpers.h"
#include "route_utils.h"

static void add_optional_string(cJSON *object, const char *key, const char *value)
{
    if (value) {
        cJSON_AddStringToObject(object, key, value);
    } else {
        cJSON_AddNullToObject(object, key);
    }
}

static cJSON *search_to_json(const bunny_db_search_t *search)
{
    cJSON *json = cJSON_CreateObject();
    cJSON_AddNumberToObject(json, "id", (double)search->id);
    cJSON_AddStringToObject(json, "site", bunny_db_site_to_string(search->site));
    cJSON_AddStringToObject(json, "label", search->label);
    cJSON_AddStringToObject(json, "query", search->query);
    cJSON_AddNumberToObject(json, "interval_hours", search->interval_hours);
    cJSON_AddStringToObject(json, "created_at", search->created_at);
    add_optional_string(json, "last_run_at", search->last_run_at);
    cJSON_AddNumberToObject(json, "unseen_count", search->unseen_count);
    return json;
}

static cJSON *post_to_json(const bunny_db_post_t *post)
{
    cJSON *json = cJSON_CreateObject();
    cJSON_AddNumberToObject(json, "id", (double)post->id);
    cJSON_AddStringToObject(json, "site", bunny_db_site_to_string(post->site));
    cJSON_AddNumberToObject(json, "external_id", (double)post->external_id);
    add_optional_string(json, "artist", post->artist);
    add_optional_string(json, "title", post->title);
    add_optional_string(json, "description", post->description);
    add_optional_string(json, "rating", post->rating);
    cJSON_AddNumberToObject(json, "score", post->score);
    cJSON_AddNumberToObject(json, "score_up", post->score_up);
    cJSON_AddNumberToObject(json, "score_down", post->score_down);
    cJSON_AddNumberToObject(json, "fav_count", post->fav_count);
    cJSON_AddNumberToObject(json, "comment_count", post->comment_count);
    add_optional_string(json, "file_url", post->file_url);
    add_optional_string(json, "file_ext", post->file_ext);
    add_optional_string(json, "file_md5", post->file_md5);
    add_optional_string(json, "preview_url", post->preview_url);
    add_optional_string(json, "sample_url", post->sample_url);
    cJSON_AddNumberToObject(json, "width", post->width);
    cJSON_AddNumberToObject(json, "height", post->height);
    add_optional_string(json, "created_at_site", post->created_at_site);
    cJSON_AddStringToObject(json, "cached_at", post->cached_at);
    cJSON_AddBoolToObject(json, "is_seen", post->is_seen);
    cJSON_AddBoolToObject(json, "is_favorited", post->is_favorited);
    return json;
}

static int handle_post_searches(struct mg_connection *conn, server_context_t *ctx)
{
    cJSON *body = server_json_read_request_body(conn);
    if (!body) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    const char *site_text = NULL;
    const char *label = NULL;
    const char *query = NULL;
    bunny_db_site_t site;
    bool valid = bunny_json_get_string(body, "site", &site_text) == BUNNY_JSON_OK && server_route_parse_site(site_text, &site) && bunny_json_get_string(body, "label", &label) == BUNNY_JSON_OK && bunny_json_get_string(body, "query", &query) == BUNNY_JSON_OK;
    int interval_hours = bunny_json_get_int_or(body, "interval_hours", 0);
    if (!valid) {
        cJSON_Delete(body);
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    int64_t search_id = 0;
    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_search_create(ctx->core, site, label, query, interval_hours, &search_id);
    pthread_mutex_unlock(&ctx->core_mutex);
    cJSON_Delete(body);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddNumberToObject(response, "id", (double)search_id);
    int status = server_json_respond(conn, 201, response);
    cJSON_Delete(response);
    return status;
}

static int handle_get_searches(struct mg_connection *conn, server_context_t *ctx)
{
    bunny_db_search_list_t list;
    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_search_list(ctx->core, &list);
    pthread_mutex_unlock(&ctx->core_mutex);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateArray();
    for (size_t i = 0; i < list.count; i++) {
        cJSON_AddItemToArray(response, search_to_json(&list.items[i]));
    }
    bunny_db_search_list_free(&list);

    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_delete_search(struct mg_connection *conn, server_context_t *ctx, int64_t search_id)
{
    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_search_delete(ctx->core, search_id);
    pthread_mutex_unlock(&ctx->core_mutex);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddBoolToObject(response, "ok", true);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_get_search_posts(struct mg_connection *conn, server_context_t *ctx, int64_t search_id, const char *query_string)
{
    bool unseen_only = false;
    if (query_string) {
        char value[8];
        if (mg_get_var(query_string, strlen(query_string), "unseen_only", value, sizeof(value)) > 0) {
            unseen_only = strcmp(value, "true") == 0 || strcmp(value, "1") == 0;
        }
    }

    bunny_db_post_list_t list;
    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_search_list_posts(ctx->core, search_id, unseen_only, &list);
    pthread_mutex_unlock(&ctx->core_mutex);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateArray();
    for (size_t i = 0; i < list.count; i++) {
        cJSON_AddItemToArray(response, post_to_json(&list.items[i]));
    }
    bunny_db_post_list_free(&list);

    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_mark_all_seen(struct mg_connection *conn, server_context_t *ctx, int64_t search_id)
{
    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_search_mark_all_seen(ctx->core, search_id);
    pthread_mutex_unlock(&ctx->core_mutex);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddBoolToObject(response, "ok", true);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int searches_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }

    const struct mg_request_info *info = mg_get_request_info(conn);
    const char *method = info->request_method;
    const char *sub_path = server_route_sub_path(info->local_uri, "/searches");

    if (strcmp(method, "POST") == 0 && !sub_path) {
        return handle_post_searches(conn, ctx);
    }
    if (strcmp(method, "GET") == 0 && !sub_path) {
        return handle_get_searches(conn, ctx);
    }

    if (sub_path) {
        int64_t search_id = 0;
        if (strcmp(method, "GET") == 0 && server_route_parse_id_with_suffix(sub_path, "posts", &search_id)) {
            return handle_get_search_posts(conn, ctx, search_id, info->query_string);
        }
        if (strcmp(method, "POST") == 0 && server_route_parse_id_with_suffix(sub_path, "mark_all_seen", &search_id)) {
            return handle_mark_all_seen(conn, ctx, search_id);
        }
        if (strcmp(method, "DELETE") == 0 && server_route_parse_id(sub_path, &search_id)) {
            return handle_delete_search(conn, ctx, search_id);
        }
    }

    return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
}

void server_routes_register_searches(struct mg_context *mg_ctx, server_context_t *ctx)
{
    mg_set_request_handler(mg_ctx, "/searches", searches_handler, ctx);
}
