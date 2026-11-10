#include "routes_slideshows.h"

#include <bunny_common/json.h>
#include <bunny_core/core.h>
#include <cJSON.h>

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "auth.h"
#include "json_helpers.h"
#include "route_utils.h"

/* Duplicated from routes_searches.c's own post_to_json/add_optional_string
 * rather than shared -- same precedent already established between
 * routes_searches.c, routes_queue.c, and the old (now-removed)
 * routes_slideshow.c (see M8.5.8's roadmap entry). */
static void add_optional_string(cJSON *object, const char *key, const char *value)
{
    if (value) {
        cJSON_AddStringToObject(object, key, value);
    } else {
        cJSON_AddNullToObject(object, key);
    }
}

static cJSON *post_to_json(const bunny_db_post_t *post)
{
    cJSON *json = cJSON_CreateObject();
    cJSON_AddNumberToObject(json, "id", (double)post->id);
    cJSON_AddStringToObject(json, "site", bunny_db_site_to_string(post->site));
    cJSON_AddNumberToObject(json, "external_id", (double)post->external_id);
    add_optional_string(json, "artist", post->artist);
    add_optional_string(json, "title", post->title);
    add_optional_string(json, "description", post->description);
    add_optional_string(json, "rating", post->rating);
    cJSON_AddNumberToObject(json, "score", post->score);
    cJSON_AddNumberToObject(json, "score_up", post->score_up);
    cJSON_AddNumberToObject(json, "score_down", post->score_down);
    cJSON_AddNumberToObject(json, "fav_count", post->fav_count);
    cJSON_AddNumberToObject(json, "comment_count", post->comment_count);
    add_optional_string(json, "file_url", post->file_url);
    add_optional_string(json, "file_ext", post->file_ext);
    add_optional_string(json, "file_md5", post->file_md5);
    add_optional_string(json, "preview_url", post->preview_url);
    add_optional_string(json, "sample_url", post->sample_url);
    cJSON_AddNumberToObject(json, "width", post->width);
    cJSON_AddNumberToObject(json, "height", post->height);
    add_optional_string(json, "created_at_site", post->created_at_site);
    cJSON_AddStringToObject(json, "cached_at", post->cached_at);
    cJSON_AddBoolToObject(json, "is_seen", post->is_seen);
    cJSON_AddBoolToObject(json, "is_favorited", post->is_favorited);
    cJSON_AddNumberToObject(json, "user_vote", post->user_vote);
    cJSON_AddNumberToObject(json, "favorite_stars", post->favorite_stars);
    return json;
}

static cJSON *slideshow_to_json(const bunny_db_slideshow_t *slideshow)
{
    cJSON *json = cJSON_CreateObject();
    cJSON_AddNumberToObject(json, "id", (double)slideshow->id);
    cJSON_AddStringToObject(json, "label", slideshow->label);
    if (slideshow->has_default_posts_per_search) {
        cJSON_AddNumberToObject(json, "default_posts_per_search", slideshow->default_posts_per_search);
    } else {
        cJSON_AddNullToObject(json, "default_posts_per_search");
    }
    if (slideshow->has_max_total_posts) {
        cJSON_AddNumberToObject(json, "max_total_posts", slideshow->max_total_posts);
    } else {
        cJSON_AddNullToObject(json, "max_total_posts");
    }
    cJSON_AddStringToObject(json, "created_at", slideshow->created_at);
    return json;
}

static cJSON *slideshow_search_to_json(const bunny_db_slideshow_search_t *item)
{
    cJSON *json = cJSON_CreateObject();
    cJSON_AddNumberToObject(json, "slideshow_id", (double)item->slideshow_id);
    cJSON_AddNumberToObject(json, "search_id", (double)item->search_id);
    if (item->has_override_count) {
        cJSON_AddNumberToObject(json, "override_count", item->override_count);
    } else {
        cJSON_AddNullToObject(json, "override_count");
    }
    cJSON_AddStringToObject(json, "added_at", item->added_at);
    return json;
}

static cJSON *slideshow_post_to_json(const bunny_db_slideshow_post_t *item)
{
    cJSON *json = cJSON_CreateObject();
    cJSON_AddNumberToObject(json, "search_id", (double)item->search_id);
    cJSON_AddItemToObject(json, "post", post_to_json(&item->post));
    return json;
}

static int handle_post_slideshows(struct mg_connection *conn, server_context_t *ctx)
{
    cJSON *body = server_json_read_request_body(conn);
    if (!body) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }
    const char *label = NULL;
    if (bunny_json_get_string(body, "label", &label) != BUNNY_JSON_OK) {
        cJSON_Delete(body);
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }
    int default_posts_per_search = 0;
    bool has_default = bunny_json_get_int(body, "default_posts_per_search", &default_posts_per_search) == BUNNY_JSON_OK;
    int max_total_posts = 0;
    bool has_max_total = bunny_json_get_int(body, "max_total_posts", &max_total_posts) == BUNNY_JSON_OK;

    int64_t slideshow_id = 0;
    bunny_core_result_t result = bunny_core_slideshow_create(ctx->core, label, has_default, default_posts_per_search, has_max_total, max_total_posts, &slideshow_id);
    cJSON_Delete(body);
    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddNumberToObject(response, "id", (double)slideshow_id);
    int status = server_json_respond(conn, 201, response);
    cJSON_Delete(response);
    return status;
}

static int handle_get_slideshows(struct mg_connection *conn, server_context_t *ctx)
{
    bunny_db_slideshow_list_t list;
    bunny_core_result_t result = bunny_core_slideshow_list(ctx->core, &list);
    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }
    cJSON *response = cJSON_CreateArray();
    for (size_t i = 0; i < list.count; i++) {
        cJSON_AddItemToArray(response, slideshow_to_json(&list.items[i]));
    }
    bunny_db_slideshow_list_free(&list);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_get_slideshow(struct mg_connection *conn, server_context_t *ctx, int64_t slideshow_id)
{
    bunny_db_slideshow_t slideshow;
    bunny_core_result_t result = bunny_core_slideshow_get(ctx->core, slideshow_id, &slideshow);
    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }
    cJSON *response = slideshow_to_json(&slideshow);
    bunny_db_slideshow_free(&slideshow);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_put_slideshow(struct mg_connection *conn, server_context_t *ctx, int64_t slideshow_id)
{
    cJSON *body = server_json_read_request_body(conn);
    if (!body) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }
    const char *label = NULL;
    if (bunny_json_get_string(body, "label", &label) != BUNNY_JSON_OK) {
        cJSON_Delete(body);
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }
    int default_posts_per_search = 0;
    bool has_default = bunny_json_get_int(body, "default_posts_per_search", &default_posts_per_search) == BUNNY_JSON_OK;
    int max_total_posts = 0;
    bool has_max_total = bunny_json_get_int(body, "max_total_posts", &max_total_posts) == BUNNY_JSON_OK;

    bunny_core_result_t result = bunny_core_slideshow_update(ctx->core, slideshow_id, label, has_default, default_posts_per_search, has_max_total, max_total_posts);
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

static int handle_delete_slideshow(struct mg_connection *conn, server_context_t *ctx, int64_t slideshow_id)
{
    bunny_core_result_t result = bunny_core_slideshow_delete(ctx->core, slideshow_id);
    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }
    cJSON *response = cJSON_CreateObject();
    cJSON_AddBoolToObject(response, "ok", true);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_get_slideshow_searches(struct mg_connection *conn, server_context_t *ctx, int64_t slideshow_id)
{
    bunny_db_slideshow_search_list_t list;
    bunny_core_result_t result = bunny_core_slideshow_search_list(ctx->core, slideshow_id, &list);
    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }
    cJSON *response = cJSON_CreateArray();
    for (size_t i = 0; i < list.count; i++) {
        cJSON_AddItemToArray(response, slideshow_search_to_json(&list.items[i]));
    }
    bunny_db_slideshow_search_list_free(&list);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

/* Adding a search link also commits its initial picks -- the client never
 * has to make a separate "now actually pick posts" call for a freshly
 * added search. */
static int handle_post_slideshow_searches(struct mg_connection *conn, server_context_t *ctx, int64_t slideshow_id)
{
    cJSON *body = server_json_read_request_body(conn);
    if (!body) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }
    int64_t search_id = 0;
    if (bunny_json_get_int64(body, "search_id", &search_id) != BUNNY_JSON_OK) {
        cJSON_Delete(body);
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }
    int override_count = 0;
    bool has_override = bunny_json_get_int(body, "override_count", &override_count) == BUNNY_JSON_OK;
    cJSON_Delete(body);

    bunny_core_result_t result = bunny_core_slideshow_search_add(ctx->core, slideshow_id, search_id, has_override, override_count);
    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }
    result = bunny_core_slideshow_search_commit_picks(ctx->core, slideshow_id, search_id);
    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateObject();
    cJSON_AddBoolToObject(response, "ok", true);
    int status = server_json_respond(conn, 201, response);
    cJSON_Delete(response);
    return status;
}

static int handle_delete_slideshow_search(struct mg_connection *conn, server_context_t *ctx, int64_t slideshow_id, int64_t search_id)
{
    bunny_core_result_t result = bunny_core_slideshow_search_remove(ctx->core, slideshow_id, search_id);
    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }
    cJSON *response = cJSON_CreateObject();
    cJSON_AddBoolToObject(response, "ok", true);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_get_slideshow_posts(struct mg_connection *conn, server_context_t *ctx, int64_t slideshow_id, const char *query_string)
{
    int64_t search_id = 0;
    if (query_string) {
        char search_id_value[32];
        if (mg_get_var(query_string, strlen(query_string), "search_id", search_id_value, sizeof(search_id_value)) > 0 && !server_route_parse_id(search_id_value, &search_id)) {
            return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
        }
    }

    bunny_db_slideshow_post_list_t list;
    bunny_core_result_t result = bunny_core_slideshow_posts_list(ctx->core, slideshow_id, search_id, &list);
    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }
    cJSON *response = cJSON_CreateArray();
    for (size_t i = 0; i < list.count; i++) {
        cJSON_AddItemToArray(response, slideshow_post_to_json(&list.items[i]));
    }
    bunny_db_slideshow_post_list_free(&list);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_post_slideshow_reroll_all(struct mg_connection *conn, server_context_t *ctx, int64_t slideshow_id)
{
    bunny_core_result_t result = bunny_core_slideshow_reroll_all(ctx->core, slideshow_id);
    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }
    cJSON *response = cJSON_CreateObject();
    cJSON_AddBoolToObject(response, "ok", true);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_post_slideshow_reroll_search(struct mg_connection *conn, server_context_t *ctx, int64_t slideshow_id, int64_t search_id)
{
    bunny_core_result_t result = bunny_core_slideshow_reroll_search(ctx->core, slideshow_id, search_id);
    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }
    cJSON *response = cJSON_CreateObject();
    cJSON_AddBoolToObject(response, "ok", true);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int handle_post_slideshow_replace_post(struct mg_connection *conn, server_context_t *ctx, int64_t slideshow_id, int64_t search_id)
{
    cJSON *body = server_json_read_request_body(conn);
    if (!body) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }
    int64_t dead_post_id = 0;
    if (bunny_json_get_int64(body, "dead_post_id", &dead_post_id) != BUNNY_JSON_OK) {
        cJSON_Delete(body);
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }
    cJSON_Delete(body);

    bunny_core_result_t result = bunny_core_slideshow_replace_post(ctx->core, slideshow_id, search_id, dead_post_id);
    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }
    cJSON *response = cJSON_CreateObject();
    cJSON_AddBoolToObject(response, "ok", true);
    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

/* Splits `path` on '/' into up to 4 segments (no existing strtok precedent
 * in this codebase, and this needs to go one level deeper than
 * server_route_parse_id_with_suffix's own single-suffix shape) -- enough
 * for the deepest route this file has, "{id}/searches/{search_id}/reroll".
 * Returns how many segments were actually found. A segment longer than
 * its buffer, or an empty one, stops the split early (same effect as
 * "not a known route," handled by the caller falling through to 404). */
#define SLIDESHOW_PATH_SEGMENT_LEN 32
#define SLIDESHOW_PATH_MAX_SEGMENTS 4

static size_t split_path(const char *path, char segments[SLIDESHOW_PATH_MAX_SEGMENTS][SLIDESHOW_PATH_SEGMENT_LEN])
{
    size_t count = 0;
    const char *cursor = path;
    while (cursor && count < SLIDESHOW_PATH_MAX_SEGMENTS) {
        const char *slash = strchr(cursor, '/');
        size_t len = slash ? (size_t)(slash - cursor) : strlen(cursor);
        if (len == 0 || len >= SLIDESHOW_PATH_SEGMENT_LEN) {
            break;
        }
        memcpy(segments[count], cursor, len);
        segments[count][len] = '\0';
        count++;
        cursor = slash ? slash + 1 : NULL;
    }
    return count;
}

static int slideshows_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }

    const struct mg_request_info *info = mg_get_request_info(conn);
    const char *method = info->request_method;
    const char *sub_path = server_route_sub_path(info->local_uri, "/slideshows");

    if (!sub_path) {
        if (strcmp(method, "GET") == 0) {
            return handle_get_slideshows(conn, ctx);
        }
        if (strcmp(method, "POST") == 0) {
            return handle_post_slideshows(conn, ctx);
        }
        return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
    }

    char segments[SLIDESHOW_PATH_MAX_SEGMENTS][SLIDESHOW_PATH_SEGMENT_LEN];
    size_t segment_count = split_path(sub_path, segments);
    int64_t slideshow_id = 0;
    if (segment_count < 1 || !server_route_parse_id(segments[0], &slideshow_id)) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
    }

    if (segment_count == 1) {
        if (strcmp(method, "GET") == 0) {
            return handle_get_slideshow(conn, ctx, slideshow_id);
        }
        if (strcmp(method, "PUT") == 0) {
            return handle_put_slideshow(conn, ctx, slideshow_id);
        }
        if (strcmp(method, "DELETE") == 0) {
            return handle_delete_slideshow(conn, ctx, slideshow_id);
        }
    } else if (segment_count == 2 && strcmp(segments[1], "reroll") == 0 && strcmp(method, "POST") == 0) {
        return handle_post_slideshow_reroll_all(conn, ctx, slideshow_id);
    } else if (segment_count == 2 && strcmp(segments[1], "posts") == 0 && strcmp(method, "GET") == 0) {
        return handle_get_slideshow_posts(conn, ctx, slideshow_id, info->query_string);
    } else if (segment_count == 2 && strcmp(segments[1], "searches") == 0) {
        if (strcmp(method, "GET") == 0) {
            return handle_get_slideshow_searches(conn, ctx, slideshow_id);
        }
        if (strcmp(method, "POST") == 0) {
            return handle_post_slideshow_searches(conn, ctx, slideshow_id);
        }
    } else if (segment_count == 3 && strcmp(segments[1], "searches") == 0) {
        int64_t search_id = 0;
        if (server_route_parse_id(segments[2], &search_id) && strcmp(method, "DELETE") == 0) {
            return handle_delete_slideshow_search(conn, ctx, slideshow_id, search_id);
        }
    } else if (segment_count == 4 && strcmp(segments[1], "searches") == 0 && strcmp(method, "POST") == 0) {
        int64_t search_id = 0;
        if (server_route_parse_id(segments[2], &search_id)) {
            if (strcmp(segments[3], "reroll") == 0) {
                return handle_post_slideshow_reroll_search(conn, ctx, slideshow_id, search_id);
            }
            if (strcmp(segments[3], "replace") == 0) {
                return handle_post_slideshow_replace_post(conn, ctx, slideshow_id, search_id);
            }
        }
    }

    return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
}

void server_routes_register_slideshows(struct mg_context *mg_ctx, server_context_t *ctx)
{
    mg_set_request_handler(mg_ctx, "/slideshows", slideshows_handler, ctx);
}
