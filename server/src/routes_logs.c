#include "routes_logs.h"

#include <bunny_core/error.h>
#include <cJSON.h>

#include <stdlib.h>
#include <string.h>

#include "auth.h"
#include "json_helpers.h"
#include "log.h"

static int handle_get_logs(struct mg_connection *conn)
{
    char **lines = NULL;
    size_t count = server_log_snapshot(&lines);

    cJSON *response = cJSON_CreateArray();
    for (size_t i = 0; i < count; i++) {
        cJSON_AddItemToArray(response, cJSON_CreateString(lines[i]));
        free(lines[i]);
    }
    free(lines);

    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int logs_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }

    const struct mg_request_info *info = mg_get_request_info(conn);
    if (strcmp(info->request_method, "GET") == 0) {
        return handle_get_logs(conn);
    }

    return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
}

void server_routes_register_logs(struct mg_context *mg_ctx, server_context_t *ctx)
{
    mg_set_request_handler(mg_ctx, "/logs", logs_handler, ctx);
}
