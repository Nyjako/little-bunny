#include "routes_sync.h"

#include <bunny_core/error.h>
#include <cJSON.h>

#include <string.h>
#include <time.h>

#include "auth.h"
#include "json_helpers.h"

static int handle_get_sync_status(struct mg_connection *conn, server_context_t *ctx)
{
    server_sync_status_snapshot_t snapshot;
    server_sync_status_get(ctx->sync_status, &snapshot);

    cJSON *response = cJSON_CreateObject();
    cJSON_AddBoolToObject(response, "active", snapshot.active);
    if (snapshot.source) {
        cJSON_AddStringToObject(response, "source", snapshot.source);
    } else {
        cJSON_AddNullToObject(response, "source");
    }
    if (snapshot.search_label) {
        cJSON_AddStringToObject(response, "search_label", snapshot.search_label);
    } else {
        cJSON_AddNullToObject(response, "search_label");
    }
    cJSON_AddNumberToObject(response, "position", snapshot.position);
    cJSON_AddNumberToObject(response, "total", snapshot.total);
    if (snapshot.active) {
        char started_at[32];
        struct tm tm_utc;
        gmtime_r(&snapshot.started_at, &tm_utc);
        strftime(started_at, sizeof(started_at), "%Y-%m-%dT%H:%M:%SZ", &tm_utc);
        cJSON_AddStringToObject(response, "started_at", started_at);
    } else {
        cJSON_AddNullToObject(response, "started_at");
    }

    server_sync_status_snapshot_free(&snapshot);

    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_post_sync_all(struct mg_connection *conn, server_context_t *ctx)
{
    bool enqueued = sync_worker_enqueue_all(ctx->sync_worker);

    cJSON *response = cJSON_CreateObject();
    cJSON_AddBoolToObject(response, "enqueued", enqueued);
    int status = server_json_respond(conn, enqueued ? 202 : 409, response);
    cJSON_Delete(response);
    return status;
}

static int sync_status_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }

    const struct mg_request_info *info = mg_get_request_info(conn);
    if (strcmp(info->request_method, "GET") == 0) {
        return handle_get_sync_status(conn, ctx);
    }

    return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
}

static int sync_all_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }

    const struct mg_request_info *info = mg_get_request_info(conn);
    if (strcmp(info->request_method, "POST") == 0) {
        return handle_post_sync_all(conn, ctx);
    }

    return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
}

void server_routes_register_sync(struct mg_context *mg_ctx, server_context_t *ctx)
{
    mg_set_request_handler(mg_ctx, "/sync/status", sync_status_handler, ctx);
    mg_set_request_handler(mg_ctx, "/sync/all", sync_all_handler, ctx);
}
