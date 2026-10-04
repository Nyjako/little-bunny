#include "routes_pools.h"

#include <bunny_core/core.h>
#include <cJSON.h>

#include <stdbool.h>
#include <string.h>

#include "auth.h"
#include "json_helpers.h"
#include "route_utils.h"

static int handle_get_pool(struct mg_connection *conn, server_context_t *ctx, int64_t pool_id)
{
    bunny_core_pool_info_t info;
    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_fetch_pool(ctx->core, pool_id, &info);
    pthread_mutex_unlock(&ctx->core_mutex);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddNumberToObject(response, "id", (double)info.id);
    cJSON_AddStringToObject(response, "name", info.name ? info.name : "");
    cJSON_AddNumberToObject(response, "post_count", (double)info.post_count);
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

void server_routes_register_pools(struct mg_context *mg_ctx, server_context_t *ctx)
{
    mg_set_request_handler(mg_ctx, "/pools", pools_handler, ctx);
}
