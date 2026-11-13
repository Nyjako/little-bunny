#include "routes_pools.h"

#include <bunny_core/core.h>
#include <cJSON.h>

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "auth.h"
#include "json_helpers.h"
#include "route_utils.h"

static int handle_get_pool(struct mg_connection *conn, server_context_t *ctx, int64_t pool_id)
{
    bunny_core_pool_info_t info;
    bunny_core_result_t result = bunny_core_fetch_pool(ctx->core, pool_id, &info);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddNumberToObject(response, "id", (double)info.id);
    cJSON_AddStringToObject(response, "name", info.name ? info.name : "");
    cJSON_AddNumberToObject(response, "post_count", (double)info.post_count);
    if (info.description) {
        cJSON_AddStringToObject(response, "description", info.description);
    } else {
        cJSON_AddNullToObject(response, "description");
    }
    cJSON *referenced_pool_ids = cJSON_CreateArray();
    for (size_t i = 0; i < info.referenced_pool_id_count; i++) {
        cJSON_AddItemToArray(referenced_pool_ids, cJSON_CreateNumber((double)info.referenced_pool_ids[i]));
    }
    cJSON_AddItemToObject(response, "referenced_pool_ids", referenced_pool_ids);
    bunny_core_pool_info_free(&info);

    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int pools_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }

    const struct mg_request_info *info = mg_get_request_info(conn);
    const char *sub_path = server_route_sub_path(info->local_uri, "/pools");

    int64_t pool_id = 0;
    if (strcmp(info->request_method, "GET") == 0 && sub_path && server_route_parse_id(sub_path, &pool_id)) {
        return handle_get_pool(conn, ctx, pool_id);
    }

    return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
}

/* Inkbunny has no equivalent of bunny_core_fetch_pool (no "fetch pool
 * metadata by id" endpoint at all) -- this is the best substitute,
 * backfilling from whatever's already locally known via some other post
 * in the same pool. See bunny_core_inkbunny_pool_name_for_id's own doc
 * comment. */
static int handle_get_inkbunny_pool_name(struct mg_connection *conn, server_context_t *ctx, int64_t pool_id)
{
    char *name = NULL;
    bunny_core_result_t result = bunny_core_inkbunny_pool_name_for_id(ctx->core, pool_id, &name);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddNumberToObject(response, "id", (double)pool_id);
    if (name) {
        cJSON_AddStringToObject(response, "name", name);
    } else {
        cJSON_AddNullToObject(response, "name");
    }
    free(name);

    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int inkbunny_pools_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }

    const struct mg_request_info *info = mg_get_request_info(conn);
    const char *sub_path = server_route_sub_path(info->local_uri, "/inkbunny_pools");

    int64_t pool_id = 0;
    if (strcmp(info->request_method, "GET") == 0 && sub_path && server_route_parse_id(sub_path, &pool_id)) {
        return handle_get_inkbunny_pool_name(conn, ctx, pool_id);
    }

    return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
}

void server_routes_register_pools(struct mg_context *mg_ctx, server_context_t *ctx)
{
    mg_set_request_handler(mg_ctx, "/pools", pools_handler, ctx);
    mg_set_request_handler(mg_ctx, "/inkbunny_pools", inkbunny_pools_handler, ctx);
}
