#include "routes_queue.h"

#include <bunny_common/json.h>
#include <bunny_core/core.h>
#include <cJSON.h>

#include <stdbool.h>
#include <string.h>

#include "auth.h"
#include "json_helpers.h"
#include "route_utils.h"

static int respond_queued(struct mg_connection *conn)
{
    cJSON *response = cJSON_CreateObject();
    cJSON_AddBoolToObject(response, "queued", true);
    int status = server_json_respond(conn, 202, response);
    cJSON_Delete(response);
    return status;
}

static int handle_favorite_add(struct mg_connection *conn, server_context_t *ctx, int64_t post_id)
{
    cJSON *body = server_json_read_request_body(conn); /* optional -- stars only applies to Inkbunny */
    int stars = bunny_json_get_int_or(body, "stars", -1);
    cJSON_Delete(body);

    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_queue_favorite_add(ctx->core, post_id, stars);
    pthread_mutex_unlock(&ctx->core_mutex);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }
    return respond_queued(conn);
}

static int handle_favorite_remove(struct mg_connection *conn, server_context_t *ctx, int64_t post_id)
{
    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_queue_favorite_remove(ctx->core, post_id);
    pthread_mutex_unlock(&ctx->core_mutex);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }
    return respond_queued(conn);
}

static int handle_vote(struct mg_connection *conn, server_context_t *ctx, int64_t post_id)
{
    cJSON *body = server_json_read_request_body(conn);
    int score = 0;
    bool has_score = body && bunny_json_get_int(body, "score", &score) == BUNNY_JSON_OK;
    bool no_unvote = bunny_json_get_bool_or(body, "no_unvote", false);
    if (!has_score) {
        cJSON_Delete(body);
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }
    cJSON_Delete(body);

    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_queue_vote(ctx->core, post_id, score, no_unvote);
    pthread_mutex_unlock(&ctx->core_mutex);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }
    return respond_queued(conn);
}

static int handle_comment(struct mg_connection *conn, server_context_t *ctx, int64_t post_id)
{
    cJSON *body = server_json_read_request_body(conn);
    const char *comment_body = NULL;
    bool has_body = body && bunny_json_get_string(body, "body", &comment_body) == BUNNY_JSON_OK;
    bool anonymous = bunny_json_get_bool_or(body, "anonymous", false);
    if (!has_body) {
        cJSON_Delete(body);
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_queue_comment(ctx->core, post_id, comment_body, anonymous);
    pthread_mutex_unlock(&ctx->core_mutex);
    cJSON_Delete(body);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }
    return respond_queued(conn);
}

static void add_optional_string(cJSON *object, const char *key, const char *value)
{
    if (value) {
        cJSON_AddStringToObject(object, key, value);
    } else {
        cJSON_AddNullToObject(object, key);
    }
}

static cJSON *post_tag_to_json(const bunny_db_post_tag_t *tag)
{
    cJSON *json = cJSON_CreateObject();
    cJSON_AddStringToObject(json, "name", tag->name);
    add_optional_string(json, "category", tag->category);
    return json;
}

static int handle_get_post_tags(struct mg_connection *conn, server_context_t *ctx, int64_t post_id)
{
    bunny_db_post_tag_list_t list;
    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_post_get_tags_by_category(ctx->core, post_id, &list);
    pthread_mutex_unlock(&ctx->core_mutex);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateArray();
    for (size_t i = 0; i < list.count; i++) {
        cJSON_AddItemToArray(response, post_tag_to_json(&list.items[i]));
    }
    bunny_db_post_tag_list_free(&list);

    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_get_post_sources(struct mg_connection *conn, server_context_t *ctx, int64_t post_id)
{
    bunny_db_string_list_t list;
    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_post_get_sources(ctx->core, post_id, &list);
    pthread_mutex_unlock(&ctx->core_mutex);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateArray();
    for (size_t i = 0; i < list.count; i++) {
        cJSON_AddItemToArray(response, cJSON_CreateString(list.items[i]));
    }
    bunny_db_string_list_free(&list);

    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_get_post_relationships(struct mg_connection *conn, server_context_t *ctx, int64_t post_id)
{
    bunny_db_post_relationships_t relationships;
    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_post_get_relationships(ctx->core, post_id, &relationships);
    pthread_mutex_unlock(&ctx->core_mutex);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddBoolToObject(response, "has_parent", relationships.has_parent);
    if (relationships.has_parent) {
        cJSON_AddNumberToObject(response, "parent_external_id", (double)relationships.parent_external_id);
    } else {
        cJSON_AddNullToObject(response, "parent_external_id");
    }
    cJSON_AddBoolToObject(response, "has_active_children", relationships.has_active_children);
    cJSON *children = cJSON_CreateArray();
    for (size_t i = 0; i < relationships.children.count; i++) {
        cJSON_AddItemToArray(children, cJSON_CreateNumber((double)relationships.children.items[i]));
    }
    cJSON_AddItemToObject(response, "children", children);
    bunny_db_post_relationships_free(&relationships);

    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_get_post_pools(struct mg_connection *conn, server_context_t *ctx, int64_t post_id)
{
    bunny_db_int64_list_t list;
    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_post_get_pool_ids(ctx->core, post_id, &list);
    pthread_mutex_unlock(&ctx->core_mutex);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateArray();
    for (size_t i = 0; i < list.count; i++) {
        cJSON_AddItemToArray(response, cJSON_CreateNumber((double)list.items[i]));
    }
    bunny_db_int64_list_free(&list);

    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_fetch_post(struct mg_connection *conn, server_context_t *ctx, const char *query_string)
{
    char site_value[16];
    char external_id_value[32];
    bool has_site = query_string && mg_get_var(query_string, strlen(query_string), "site", site_value, sizeof(site_value)) > 0;
    bool has_external_id = query_string && mg_get_var(query_string, strlen(query_string), "external_id", external_id_value, sizeof(external_id_value)) > 0;

    bunny_db_site_t site;
    int64_t external_id = 0;
    if (!has_site || !server_route_parse_site(site_value, &site) || !has_external_id || !server_route_parse_id(external_id_value, &external_id)) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    int64_t post_id = 0;
    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_fetch_and_cache_post(ctx->core, site, external_id, &post_id);
    pthread_mutex_unlock(&ctx->core_mutex);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddNumberToObject(response, "id", (double)post_id);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_mark_seen(struct mg_connection *conn, server_context_t *ctx, int64_t post_id)
{
    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_post_mark_seen(ctx->core, post_id);
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

static int posts_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }

    const struct mg_request_info *info = mg_get_request_info(conn);
    const char *method = info->request_method;
    const char *sub_path = server_route_sub_path(info->local_uri, "/posts");
    if (!sub_path) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
    }

    int64_t post_id = 0;
    if (strcmp(method, "POST") == 0 && server_route_parse_id_with_suffix(sub_path, "favorite", &post_id)) {
        return handle_favorite_add(conn, ctx, post_id);
    }
    if (strcmp(method, "DELETE") == 0 && server_route_parse_id_with_suffix(sub_path, "favorite", &post_id)) {
        return handle_favorite_remove(conn, ctx, post_id);
    }
    if (strcmp(method, "POST") == 0 && server_route_parse_id_with_suffix(sub_path, "vote", &post_id)) {
        return handle_vote(conn, ctx, post_id);
    }
    if (strcmp(method, "POST") == 0 && server_route_parse_id_with_suffix(sub_path, "comment", &post_id)) {
        return handle_comment(conn, ctx, post_id);
    }
    if (strcmp(method, "POST") == 0 && server_route_parse_id_with_suffix(sub_path, "seen", &post_id)) {
        return handle_mark_seen(conn, ctx, post_id);
    }
    if (strcmp(method, "GET") == 0 && server_route_parse_id_with_suffix(sub_path, "tags", &post_id)) {
        return handle_get_post_tags(conn, ctx, post_id);
    }
    if (strcmp(method, "GET") == 0 && server_route_parse_id_with_suffix(sub_path, "sources", &post_id)) {
        return handle_get_post_sources(conn, ctx, post_id);
    }
    if (strcmp(method, "GET") == 0 && server_route_parse_id_with_suffix(sub_path, "relationships", &post_id)) {
        return handle_get_post_relationships(conn, ctx, post_id);
    }
    if (strcmp(method, "GET") == 0 && server_route_parse_id_with_suffix(sub_path, "pools", &post_id)) {
        return handle_get_post_pools(conn, ctx, post_id);
    }
    if (strcmp(method, "POST") == 0 && strcmp(sub_path, "fetch") == 0) {
        return handle_fetch_post(conn, ctx, info->query_string);
    }

    return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
}

static int handle_sync(struct mg_connection *conn, server_context_t *ctx)
{
    bunny_core_sync_stats_t stats;
    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_sync_due_searches(ctx->core, &stats);
    pthread_mutex_unlock(&ctx->core_mutex);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddNumberToObject(response, "searches_checked", stats.searches_checked);
    cJSON_AddNumberToObject(response, "searches_synced", stats.searches_synced);
    cJSON_AddNumberToObject(response, "posts_upserted", stats.posts_upserted);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int sync_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }
    const struct mg_request_info *info = mg_get_request_info(conn);
    if (strcmp(info->request_method, "POST") != 0) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
    }
    return handle_sync(conn, ctx);
}

static int handle_queue_process(struct mg_connection *conn, server_context_t *ctx)
{
    bunny_core_queue_stats_t stats;
    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_process_queue(ctx->core, &stats);
    pthread_mutex_unlock(&ctx->core_mutex);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddNumberToObject(response, "actions_processed", stats.actions_processed);
    cJSON_AddNumberToObject(response, "actions_succeeded", stats.actions_succeeded);
    cJSON_AddNumberToObject(response, "actions_failed", stats.actions_failed);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int queue_process_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }
    const struct mg_request_info *info = mg_get_request_info(conn);
    if (strcmp(info->request_method, "POST") != 0) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
    }
    return handle_queue_process(conn, ctx);
}

void server_routes_register_queue(struct mg_context *mg_ctx, server_context_t *ctx)
{
    mg_set_request_handler(mg_ctx, "/posts", posts_handler, ctx);
    mg_set_request_handler(mg_ctx, "/sync", sync_handler, ctx);
    mg_set_request_handler(mg_ctx, "/queue/process", queue_process_handler, ctx);
}
