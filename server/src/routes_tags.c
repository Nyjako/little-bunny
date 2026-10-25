#include "routes_tags.h"

#include <bunny_core/core.h>
#include <cJSON.h>

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "auth.h"
#include "json_helpers.h"
#include "route_utils.h"

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
    cJSON_AddStringToObject(response, "computed_at", report->computed_at);
    cJSON_AddItemToObject(response, "top_favorited_tags", tag_stat_list_to_json(&report->top_favorited_tags));
    cJSON_AddItemToObject(response, "top_used_tags", tag_stat_list_to_json(&report->top_used_tags));
    cJSON_AddItemToObject(response, "top_pools", tag_stat_list_to_json(&report->top_pools));
    cJSON_AddItemToObject(response, "top_viewed_searches", tag_stat_list_to_json(&report->top_viewed_searches));

    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

/* GET returns the tag-stats screen's unified report (M40), cached for up to
 * 24h; POST forces a recompute (the screen's manual refresh action). Both
 * share this one handler/route since they differ only in which bunny_core
 * entry point builds the report. */
static int handle_stats_report(struct mg_connection *conn, server_context_t *ctx, const char *method)
{
    bunny_core_stats_report_t report;
    bunny_core_result_t result = strcmp(method, "POST") == 0 ? bunny_core_refresh_stats_report(ctx->core, &report) : bunny_core_get_stats_report(ctx->core, &report);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
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
