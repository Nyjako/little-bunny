#ifndef BUNNY_SERVER_JSON_HELPERS_H
#define BUNNY_SERVER_JSON_HELPERS_H

#include <bunny_core/error.h>
#include <cJSON.h>
#include <civetweb.h>

/* Reads the full request body from `conn` and parses it as JSON. Returns
 * NULL if the body is empty/absent, too large, or isn't valid JSON --
 * callers should treat that as BUNNY_CORE_ERR_INVALID_ARG. Caller owns the
 * result (cJSON_Delete). */
cJSON *server_json_read_request_body(struct mg_connection *conn);

/* Writes `body` (owned by the caller, not freed here) as the JSON response
 * with the given HTTP status. Returns `status`, for the caller to propagate
 * as the civetweb handler's own return value (used for access-log status). */
int server_json_respond(struct mg_connection *conn, int status, const cJSON *body);

/* Writes {"error": "..."} with a status derived from `result` (400 for
 * ERR_INVALID_ARG, 404 for ERR_NOT_FOUND, 502 for ERR_SITE, 500 otherwise).
 * Returns the status used, same convention as server_json_respond. */
int server_json_respond_error(struct mg_connection *conn, bunny_core_result_t result);

#endif /* BUNNY_SERVER_JSON_HELPERS_H */
