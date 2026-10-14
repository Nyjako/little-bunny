#include "routes_blacklist.h"

#include <bunny_common/json.h>
#include <bunny_core/core.h>
#include <cJSON.h>

#include <stdbool.h>
#include <string.h>

#include "auth.h"
#include "json_helpers.h"
#include "route_utils.h"

static int handle_get_blacklist(struct mg_connection *conn, server_context_t *ctx, const char *query_string)
{
    char site_value[16];
    bool has_site = query_string && mg_get_var(query_string, strlen(query_string), "site", site_value, sizeof(site_value)) > 0;

    bunny_db_site_t site;
    if (!has_site || !server_route_parse_site(site_value, &site)) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    bunny_db_string_list_t list;
    bunny_core_result_t result = bunny_core_blacklist_list(ctx->core, site, &list);

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

static int handle_post_blacklist(struct mg_connection *conn, server_context_t *ctx)
{
    cJSON *body = server_json_read_request_body(conn);
    if (!body) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    const char *site_text = NULL;
    const char *tag = NULL;
    bunny_db_site_t site;
    bool valid = bunny_json_get_string(body, "site", &site_text) == BUNNY_JSON_OK && server_route_parse_site(site_text, &site) && bunny_json_get_string(body, "tag", &tag) == BUNNY_JSON_OK;
    if (!valid) {
        cJSON_Delete(body);
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    bunny_core_result_t result = bunny_core_blacklist_add(ctx->core, site, tag);
    cJSON_Delete(body);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddBoolToObject(response, "ok", true);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_delete_blacklist(struct mg_connection *conn, server_context_t *ctx, const char *query_string)
{
    char site_value[16];
    char tag_value[256];
    bool has_site = query_string && mg_get_var(query_string, strlen(query_string), "site", site_value, sizeof(site_value)) > 0;
    bool has_tag = query_string && mg_get_var(query_string, strlen(query_string), "tag", tag_value, sizeof(tag_value)) > 0;

    bunny_db_site_t site;
    if (!has_site || !server_route_parse_site(site_value, &site) || !has_tag) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    bunny_core_result_t result = bunny_core_blacklist_remove(ctx->core, site, tag_value);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddBoolToObject(response, "ok", true);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int blacklist_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }

    const struct mg_request_info *info = mg_get_request_info(conn);
    const char *method = info->request_method;

    if (strcmp(method, "GET") == 0) {
        return handle_get_blacklist(conn, ctx, info->query_string);
    }
    if (strcmp(method, "POST") == 0) {
        return handle_post_blacklist(conn, ctx);
    }
    if (strcmp(method, "DELETE") == 0) {
        return handle_delete_blacklist(conn, ctx, info->query_string);
    }

    return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
}

void server_routes_register_blacklist(struct mg_context *mg_ctx, server_context_t *ctx)
{
    mg_set_request_handler(mg_ctx, "/blacklist", blacklist_handler, ctx);
}
