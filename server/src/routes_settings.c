#include "routes_settings.h"

#include <bunny_core/core.h>
#include <bunny_core/error.h>
#include <cJSON.h>

#include <string.h>

#include "auth.h"
#include "json_helpers.h"

static int handle_get_settings(struct mg_connection *conn, server_context_t *ctx)
{
    int hours = 24;
    bunny_core_result_t result = bunny_core_get_default_sync_interval_hours(ctx->core, &hours);
    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddNumberToObject(response, "default_sync_interval_hours", hours);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_put_settings(struct mg_connection *conn, server_context_t *ctx)
{
    cJSON *body = server_json_read_request_body(conn);
    if (!body) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    cJSON *hours_item = cJSON_GetObjectItemCaseSensitive(body, "default_sync_interval_hours");
    if (!cJSON_IsNumber(hours_item) || hours_item->valueint <= 0) {
        cJSON_Delete(body);
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    bunny_core_result_t result = bunny_core_set_default_sync_interval_hours(ctx->core, hours_item->valueint);
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

static int settings_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }

    const struct mg_request_info *info = mg_get_request_info(conn);
    if (strcmp(info->request_method, "GET") == 0) {
        return handle_get_settings(conn, ctx);
    }
    if (strcmp(info->request_method, "PUT") == 0) {
        return handle_put_settings(conn, ctx);
    }

    return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
}

void server_routes_register_settings(struct mg_context *mg_ctx, server_context_t *ctx)
{
    mg_set_request_handler(mg_ctx, "/settings", settings_handler, ctx);
}
