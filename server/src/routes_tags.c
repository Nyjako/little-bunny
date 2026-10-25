#include "routes_tags.h"

#include <bunny_core/core.h>
#include <cJSON.h>

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "auth.h"
#include "json_helpers.h"
#include "route_utils.h"
#include "task_queue.h"

static int handle_get_tags_autocomplete(struct mg_connection *conn, server_context_t *ctx, const char *query_string)
{
    char site_value[16];
    char prefix_value[256];
    char limit_value[16];
    bool has_site = query_string && mg_get_var(query_string, strlen(query_string), "site", site_value, sizeof(site_value)) > 0;
    bool has_prefix = query_string && mg_get_var(query_string, strlen(query_string), "prefix", prefix_value, sizeof(prefix_value)) > 0;

    bunny_db_site_t site;
    if (!has_site || !server_route_parse_site(site_value, &site) || !has_prefix) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    int limit = 10;
    if (mg_get_var(query_string, strlen(query_string), "limit", limit_value, sizeof(limit_value)) > 0) {
        limit = atoi(limit_value);
    }

    bunny_db_tag_stat_list_t list;
    bunny_core_result_t result = bunny_core_tag_autocomplete(ctx->core, site, prefix_value, limit, &list);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateArray();
    for (size_t i = 0; i < list.count; i++) {
        cJSON *item = cJSON_CreateObject();
        cJSON_AddStringToObject(item, "name", list.items[i].name);
        cJSON_AddNumberToObject(item, "count", list.items[i].count);
        cJSON_AddItemToArray(response, item);
    }
    bunny_db_tag_stat_list_free(&list);

    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static cJSON *tag_stat_list_to_json(const bunny_db_tag_stat_list_t *list)
{
    cJSON *array = cJSON_CreateArray();
    for (size_t i = 0; i < list->count; i++) {
        cJSON *item = cJSON_CreateObject();
        cJSON_AddStringToObject(item, "name", list->items[i].name);
        cJSON_AddNumberToObject(item, "count", list->items[i].count);
        cJSON_AddItemToArray(array, item);
    }
    return array;
}

static int respond_with_stats_report(struct mg_connection *conn, const bunny_core_stats_report_t *report)
{
    cJSON *response = cJSON_CreateObject();
    if (report->computed_at) {
        cJSON_AddStringToObject(response, "computed_at", report->computed_at);
    } else {
        cJSON_AddNullToObject(response, "computed_at");
    }
    cJSON_AddItemToObject(response, "top_favorited_tags", tag_stat_list_to_json(&report->top_favorited_tags));
    cJSON_AddItemToObject(response, "top_used_tags", tag_stat_list_to_json(&report->top_used_tags));
    cJSON_AddItemToObject(response, "top_pools", tag_stat_list_to_json(&report->top_pools));
    cJSON_AddItemToObject(response, "top_viewed_searches", tag_stat_list_to_json(&report->top_viewed_searches));

    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

/* Both GET and POST only ever read whatever's already cached (M55) --
 * neither blocks a civetweb worker thread building the report inline, which
 * is what used to hang the server on a large enough database (the same
 * class of bug M39/M40/M46 already fixed elsewhere). GET enqueues a
 * background rebuild only when the cache is missing or stale; POST (the
 * screen's manual refresh action) always enqueues one, as a "force" --
 * either way the enqueue is fire-and-forget (task_queue dedupes against an
 * already-pending/running build, see TASK_TYPE_BUILD_STATS_REPORT in
 * task_queue.c) and the response is whatever was cached *before* this
 * request, which may still be stale or even entirely empty the very first
 * time. The client is expected to just re-fetch later to see the result,
 * the same way it already would for any other background task. */
static int handle_stats_report(struct mg_connection *conn, server_context_t *ctx, const char *method)
{
    bunny_core_stats_report_t report;
    bool has_cache = false;
    bool is_stale = false;
    bunny_core_result_t result = bunny_core_get_cached_stats_report(ctx->core, &report, &has_cache, &is_stale);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    bool force_refresh = strcmp(method, "POST") == 0;
    if (force_refresh || !has_cache || is_stale) {
        task_queue_enqueue_stats_report_build(ctx->task_queue);
    }

    int status = respond_with_stats_report(conn, &report);
    bunny_core_stats_report_free(&report);
    return status;
}

static int tags_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }

    const struct mg_request_info *info = mg_get_request_info(conn);
    if (strcmp(info->request_method, "GET") == 0 && strcmp(info->local_uri, "/tags/autocomplete") == 0) {
        return handle_get_tags_autocomplete(conn, ctx, info->query_string);
    }
    if ((strcmp(info->request_method, "GET") == 0 || strcmp(info->request_method, "POST") == 0) && strcmp(info->local_uri, "/stats_report") == 0) {
        return handle_stats_report(conn, ctx, info->request_method);
    }

    return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
}

void server_routes_register_tags(struct mg_context *mg_ctx, server_context_t *ctx)
{
    mg_set_request_handler(mg_ctx, "/tags/autocomplete", tags_handler, ctx);
    mg_set_request_handler(mg_ctx, "/stats_report", tags_handler, ctx);
}
