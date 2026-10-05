#include "routes_search.h"

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

static int handle_preview_search(struct mg_connection *conn, server_context_t *ctx, const char *query_string)
{
    char site_value[16];
    char query_value[1024];
    bool has_site = query_string && mg_get_var(query_string, strlen(query_string), "site", site_value, sizeof(site_value)) > 0;
    bool has_query = query_string && mg_get_var(query_string, strlen(query_string), "query", query_value, sizeof(query_value)) > 0;

    bunny_db_site_t site;
    if (!has_site || !server_route_parse_site(site_value, &site) || !has_query) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    bunny_db_post_list_t posts;
    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_preview_search(ctx->core, site, query_value, &posts);
    pthread_mutex_unlock(&ctx->core_mutex);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateArray();
    for (size_t i = 0; i < posts.count; i++) {
        cJSON_AddItemToArray(response, post_to_json(&posts.items[i]));
    }
    bunny_db_post_list_free(&posts);

    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int search_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }

    const struct mg_request_info *info = mg_get_request_info(conn);
    const char *sub_path = server_route_sub_path(info->local_uri, "/search");

    if (strcmp(info->request_method, "POST") == 0 && sub_path && strcmp(sub_path, "preview") == 0) {
        return handle_preview_search(conn, ctx, info->query_string);
    }

    return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
}

void server_routes_register_search(struct mg_context *mg_ctx, server_context_t *ctx)
{
    mg_set_request_handler(mg_ctx, "/search", search_handler, ctx);
}
