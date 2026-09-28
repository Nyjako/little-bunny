#include "json_helpers.h"

#include <stdlib.h>
#include <string.h>

#define SERVER_JSON_MAX_BODY_BYTES (64 * 1024)

cJSON *server_json_read_request_body(struct mg_connection *conn)
{
    const struct mg_request_info *info = mg_get_request_info(conn);
    if (!info || info->content_length <= 0 || info->content_length > SERVER_JSON_MAX_BODY_BYTES) {
        return NULL;
    }

    size_t len = (size_t)info->content_length;
    char *buf = malloc(len + 1);
    if (!buf) {
        return NULL;
    }

    size_t total_read = 0;
    while (total_read < len) {
        int n = mg_read(conn, buf + total_read, len - total_read);
        if (n <= 0) {
            break;
        }
        total_read += (size_t)n;
    }
    buf[total_read] = '\0';

    cJSON *json = cJSON_ParseWithLength(buf, total_read);
    free(buf);
    return json;
}

static const char *status_text_for(int status)
{
    switch (status) {
        case 200:
            return "OK";
        case 201:
            return "Created";
        case 202:
            return "Accepted";
        case 400:
            return "Bad Request";
        case 401:
            return "Unauthorized";
        case 404:
            return "Not Found";
        case 502:
            return "Bad Gateway";
        default:
            return "Internal Server Error";
    }
}

int server_json_respond(struct mg_connection *conn, int status, const cJSON *body)
{
    char *text = body ? cJSON_PrintUnformatted(body) : NULL;
    const char *safe_text = text ? text : "{}";

    mg_printf(conn,
              "HTTP/1.1 %d %s\r\n"
              "Content-Type: application/json\r\n"
              "Content-Length: %d\r\n"
              "Connection: close\r\n\r\n"
              "%s",
              status, status_text_for(status), (int)strlen(safe_text), safe_text);

    free(text);
    return status;
}

int server_json_respond_error(struct mg_connection *conn, bunny_core_result_t result)
{
    int status;
    switch (result) {
        case BUNNY_CORE_ERR_INVALID_ARG:
            status = 400;
            break;
        case BUNNY_CORE_ERR_NOT_FOUND:
            status = 404;
            break;
        case BUNNY_CORE_ERR_SITE:
            status = 502;
            break;
        default:
            status = 500;
            break;
    }

    cJSON *body = cJSON_CreateObject();
    cJSON_AddStringToObject(body, "error", bunny_core_result_to_string(result));
    int returned_status = server_json_respond(conn, status, body);
    cJSON_Delete(body);
    return returned_status;
}
