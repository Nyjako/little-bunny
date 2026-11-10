#include "routes_slideshow.h"

#include <bunny_core/core.h>
#include <cJSON.h>

#include <stdlib.h>
#include <string.h>

#include "auth.h"
#include "json_helpers.h"
#include "route_utils.h"

/* Duplicated from routes_searches.c's own post_to_json/add_optional_string
 * rather than shared -- same precedent already established between
 * routes_searches.c and routes_queue.c (see M8.5.8's roadmap entry). */
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

/* Parses a comma-separated list of positive int64 ids (e.g. "1,2,3") into a
 * malloc'd array -- no existing precedent for a comma-list query param in
 * this codebase (every other multi-value param here is a single int/string),
 * so this is new. Two passes over `text`: first counts commas to size the
 * array, second actually parses each token via server_route_parse_id (same
 * validation every other int-ish query param in this codebase already
 * goes through). Returns false (leaving *out_ids/*out_count untouched) on
 * any malformed token or allocation failure -- caller responds 400. */
static bool parse_id_list(const char *text, int64_t **out_ids, size_t *out_count)
{
    if (!text || !*text) {
        return false;
    }
    size_t count = 1;
    for (const char *p = text; *p; p++) {
        if (*p == ',') {
            count++;
        }
    }

    int64_t *ids = malloc(count * sizeof(int64_t));
    if (!ids) {
        return false;
    }

    char *copy = strdup(text);
    if (!copy) {
        free(ids);
        return false;
    }

    size_t parsed = 0;
    char *cursor = copy;
    while (cursor) {
        char *comma = strchr(cursor, ',');
        if (comma) {
            *comma = '\0';
        }
        int64_t id = 0;
        if (!server_route_parse_id(cursor, &id)) {
            free(copy);
            free(ids);
            return false;
        }
        ids[parsed++] = id;
        cursor = comma ? comma + 1 : NULL;
    }
    free(copy);

    *out_ids = ids;
    *out_count = parsed;
    return true;
}

static int handle_get_slideshow_posts(struct mg_connection *conn, server_context_t *ctx, const char *query_string)
{
    char search_ids_value[2048];
    if (!query_string || mg_get_var(query_string, strlen(query_string), "search_ids", search_ids_value, sizeof(search_ids_value)) <= 0) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }
    int64_t *search_ids = NULL;
    size_t search_id_count = 0;
    if (!parse_id_list(search_ids_value, &search_ids, &search_id_count)) {
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    char count_value[16];
    int64_t count = 0;
    if (mg_get_var(query_string, strlen(query_string), "count", count_value, sizeof(count_value)) <= 0 || !server_route_parse_id(count_value, &count)) {
        free(search_ids);
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    char rating_mask_value[16];
    int64_t rating_mask = BUNNY_DB_RATING_MASK_ALL;
    if (mg_get_var(query_string, strlen(query_string), "rating_mask", rating_mask_value, sizeof(rating_mask_value)) > 0 && !server_route_parse_id(rating_mask_value, &rating_mask)) {
        free(search_ids);
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    char media_mask_value[16];
    int64_t media_mask = BUNNY_DB_MEDIA_MASK_ALL;
    if (mg_get_var(query_string, strlen(query_string), "media_mask", media_mask_value, sizeof(media_mask_value)) > 0 && !server_route_parse_id(media_mask_value, &media_mask)) {
        free(search_ids);
        return server_json_respond_error(conn, BUNNY_CORE_ERR_INVALID_ARG);
    }

    bunny_db_post_list_t list;
    bunny_core_result_t result = bunny_core_slideshow_pick_random_posts(ctx->core, search_ids, search_id_count, (int)rating_mask, (int)media_mask, (int)count, &list);
    free(search_ids);

    if (result != BUNNY_CORE_OK) {
        return server_json_respond_error(conn, result);
    }

    cJSON *response = cJSON_CreateArray();
    for (size_t i = 0; i < list.count; i++) {
        cJSON_AddItemToArray(response, post_to_json(&list.items[i]));
    }
    bunny_db_post_list_free(&list);

    int status = server_json_respond(conn, 200, response);
    cJSON_Delete(response);
    return status;
}

static int slideshow_posts_handler(struct mg_connection *conn, void *cbdata)
{
    server_context_t *ctx = (server_context_t *)cbdata;
    if (!server_auth_check_request(ctx->auth, conn)) {
        return 401;
    }

    const struct mg_request_info *info = mg_get_request_info(conn);
    if (strcmp(info->request_method, "GET") == 0) {
        return handle_get_slideshow_posts(conn, ctx, info->query_string);
    }

    return server_json_respond_error(conn, BUNNY_CORE_ERR_NOT_FOUND);
}

void server_routes_register_slideshow(struct mg_context *mg_ctx, server_context_t *ctx)
{
    mg_set_request_handler(mg_ctx, "/slideshow/posts", slideshow_posts_handler, ctx);
}
