#include "routes_tasks.h"

#include <bunny_core/error.h>
#include <cJSON.h>

#include <string.h>
#include <time.h>

#include "auth.h"
#include "json_helpers.h"

static const char *priority_to_string(task_priority_t priority)
{
    switch (priority) {
        case TASK_PRIORITY_HIGH:
            return "high";
        case TASK_PRIORITY_MEDIUM:
            return "medium";
        case TASK_PRIORITY_LOW:
        default:
            return "low";
    }
}

static const char *status_to_string(task_status_t status)
{
    return status == TASK_STATUS_RUNNING ? "running" : "pending";
}

static const char *type_to_string(task_type_t type)
{
    switch (type) {
        case TASK_TYPE_SYNC_SEARCH:
            return "sync_search";
        case TASK_TYPE_SYNC_ALL:
            return "sync_all";
        case TASK_TYPE_SYNC_DUE:
            return "sync_due";
        case TASK_TYPE_PROCESS_ACTION_QUEUE:
            return "process_action_queue";
        default:
            return "unknown";
    }
}

static cJSON *entry_to_json(const task_queue_entry_t *entry)
{
    cJSON *json = cJSON_CreateObject();
    cJSON_AddNumberToObject(json, "id", (double)entry->id);
    cJSON_AddStringToObject(json, "type", type_to_string(entry->type));
    cJSON_AddStringToObject(json, "priority", priority_to_string(entry->priority));
    cJSON_AddStringToObject(json, "status", status_to_string(entry->status));
    cJSON_AddStringToObject(json, "label", entry->label);

    char enqueued_at[32];
    struct tm tm_utc;
#ifdef _WIN32
    gmtime_s(&tm_utc, &entry->enqueued_at);
#else
    gmtime_r(&entry->enqueued_at, &tm_utc);
#endif
    strftime(enqueued_at, sizeof(enqueued_at), "%Y-%m-%dT%H:%M:%SZ", &tm_utc);
    cJSON_AddStringToObject(json, "enqueued_at", enqueued_at);

    return json;
}

static int handle_get_tasks(struct mg_connection *conn, server_context_t *ctx)
{
    task_queue_snapshot_t snapshot;
    task_queue_snapshot_get(ctx->task_queue, &snapshot);

    cJSON *response = cJSON_CreateArray();
    for (size_t i = 0; i < snapshot.count; i++) {
        cJSON_AddItemToArray(response, entry_to_json(&snapshot.items[i]));
    }
    task_queue_snapshot_free(&snapshot);

    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int tasks_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }

    const struct mg_request_info *info = mg_get_request_info(conn);
    if (strcmp(info->request_method, "GET") == 0) {
        return handle_get_tasks(conn, ctx);
    }

    return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
}

void server_routes_register_tasks(struct mg_context *mg_ctx, server_context_t *ctx)
{
    mg_set_request_handler(mg_ctx, "/tasks", tasks_handler, ctx);
}
