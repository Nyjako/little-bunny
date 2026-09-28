#include "routes_accounts.h"

#include <bunny_common/json.h>
#include <bunny_core/core.h>
#include <cJSON.h>

#include <string.h>

#include "auth.h"
#include "json_helpers.h"
#include "route_utils.h"

static int handle_post_accounts(struct mg_connection *conn, server_context_t *ctx)
{
    cJSON *body = server_json_read_request_body(conn);
    if (!body) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    const char *site_text = NULL;
    const char *username = NULL;
    const char *secret = NULL;
    bunny_db_site_t site;
    bool valid = bunny_json_get_string(body, "site", &site_text) == BUNNY_JSON_OK && server_route_parse_site(site_text, &site) && bunny_json_get_string(body, "username", &username) == BUNNY_JSON_OK && bunny_json_get_string(body, "secret", &secret) == BUNNY_JSON_OK;
    if (!valid) {
        cJSON_Delete(body);
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_account_set(ctx->core, site, username, secret);
    pthread_mutex_unlock(&ctx->core_mutex);
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

static int handle_get_account(struct mg_connection *conn, server_context_t *ctx, const char *site_text)
{
    bunny_db_site_t site;
    if (!server_route_parse_site(site_text, &site)) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    bunny_db_account_t account;
    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_account_get(ctx->core, site, &account);
    pthread_mutex_unlock(&ctx->core_mutex);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddNumberToObject(response, "id", (double)account.id);
    cJSON_AddStringToObject(response, "site", bunny_db_site_to_string(account.site));
    cJSON_AddStringToObject(response, "username", account.username);
    cJSON_AddStringToObject(response, "created_at", account.created_at);
    bunny_db_account_free(&account);

    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_delete_account(struct mg_connection *conn, server_context_t *ctx, const char *site_text)
{
    bunny_db_site_t site;
    if (!server_route_parse_site(site_text, &site)) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    pthread_mutex_lock(&ctx->core_mutex);
    bunny_core_result_t result = bunny_core_account_delete(ctx->core, site);
    pthread_mutex_unlock(&ctx->core_mutex);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddBoolToObject(response, "ok", true);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int accounts_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }

    const struct mg_request_info *info = mg_get_request_info(conn);
    const char *method = info->request_method;
    const char *site_text = server_route_sub_path(info->local_uri, "/accounts");

    if (strcmp(method, "POST") == 0 && !site_text) {
        return handle_post_accounts(conn, ctx);
    }
    if (strcmp(method, "GET") == 0 && site_text) {
        return handle_get_account(conn, ctx, site_text);
    }
    if (strcmp(method, "DELETE") == 0 && site_text) {
        return handle_delete_account(conn, ctx, site_text);
    }

    return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
}

void server_routes_register_accounts(struct mg_context *mg_ctx, server_context_t *ctx)
{
    mg_set_request_handler(mg_ctx, "/accounts", accounts_handler, ctx);
}
