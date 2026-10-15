#include "routes_groups.h"

#include <bunny_common/json.h>
#include <bunny_core/core.h>
#include <cJSON.h>

#include <stdbool.h>
#include <string.h>

#include "auth.h"
#include "json_helpers.h"
#include "route_utils.h"

static cJSON *group_to_json(const bunny_db_group_t *group)
{
    cJSON *json = cJSON_CreateObject();
    cJSON_AddNumberToObject(json, "id", (double)group->id);
    cJSON_AddStringToObject(json, "name", group->name);
    cJSON_AddBoolToObject(json, "pinned", group->pinned);
    cJSON_AddStringToObject(json, "created_at", group->created_at);
    return json;
}

static int handle_post_groups(struct mg_connection *conn, server_context_t *ctx)
{
    cJSON *body = server_json_read_request_body(conn);
    if (!body) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    const char *name = NULL;
    bool valid = bunny_json_get_string(body, "name", &name) == BUNNY_JSON_OK;
    bool pinned = bunny_json_get_bool_or(body, "pinned", false);
    if (!valid) {
        cJSON_Delete(body);
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    int64_t group_id = 0;
    bunny_core_result_t result = bunny_core_group_create(ctx->core, name, pinned, &group_id);
    cJSON_Delete(body);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddNumberToObject(response, "id", (double)group_id);
    int status = server_json_respond(conn, 201, response);
    cJSON_Delete(response);
    return status;
}

static int handle_get_groups(struct mg_connection *conn, server_context_t *ctx)
{
    bunny_db_group_list_t list;
    bunny_core_result_t result = bunny_core_group_list(ctx->core, &list);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateArray();
    for (size_t i = 0; i < list.count; i++) {
        cJSON_AddItemToArray(response, group_to_json(&list.items[i]));
    }
    bunny_db_group_list_free(&list);

    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_put_group(struct mg_connection *conn, server_context_t *ctx, int64_t group_id)
{
    cJSON *body = server_json_read_request_body(conn);
    if (!body) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    const char *name = NULL;
    bool valid = bunny_json_get_string(body, "name", &name) == BUNNY_JSON_OK;
    bool pinned = bunny_json_get_bool_or(body, "pinned", false);
    if (!valid) {
        cJSON_Delete(body);
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    bunny_core_result_t result = bunny_core_group_update(ctx->core, group_id, name, pinned);
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

static int handle_delete_group(struct mg_connection *conn, server_context_t *ctx, int64_t group_id)
{
    bunny_core_result_t result = bunny_core_group_delete(ctx->core, group_id);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddBoolToObject(response, "ok", true);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int groups_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }

    const struct mg_request_info *info = mg_get_request_info(conn);
    const char *method = info->request_method;
    const char *sub_path = server_route_sub_path(info->local_uri, "/groups");

    if (strcmp(method, "POST") == 0 && !sub_path) {
        return handle_post_groups(conn, ctx);
    }
    if (strcmp(method, "GET") == 0 && !sub_path) {
        return handle_get_groups(conn, ctx);
    }

    if (sub_path) {
        int64_t group_id = 0;
        if (strcmp(method, "PUT") == 0 && server_route_parse_id(sub_path, &group_id)) {
            return handle_put_group(conn, ctx, group_id);
        }
        if (strcmp(method, "DELETE") == 0 && server_route_parse_id(sub_path, &group_id)) {
            return handle_delete_group(conn, ctx, group_id);
        }
    }

    return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
}

void server_routes_register_groups(struct mg_context *mg_ctx, server_context_t *ctx)
{
    mg_set_request_handler(mg_ctx, "/groups", groups_handler, ctx);
}
