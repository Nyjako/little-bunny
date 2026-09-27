#include "inkbunny/types.h"

#include <stdlib.h>
#include <string.h>

#include "internal.h"

static char *dup_or_null(const char *s) {
    return s ? strdup(s) : NULL;
}

static void parse_file(const cJSON *file_obj, inkbunny_file_t *out) {
    memset(out, 0, sizeof(*out));
    if (!file_obj) {
        return;
    }
    out->file_id = inkbunny_field_int64(file_obj, "file_id", 0);
    out->file_name = dup_or_null(bunny_json_get_string_or(file_obj, "file_name", NULL));
    out->url_full = dup_or_null(bunny_json_get_string_or(file_obj, "file_url_full", NULL));
    out->url_screen = dup_or_null(bunny_json_get_string_or(file_obj, "file_url_screen", NULL));
    out->url_preview = dup_or_null(bunny_json_get_string_or(file_obj, "file_url_preview", NULL));
    out->mimetype = dup_or_null(bunny_json_get_string_or(file_obj, "mimetype", NULL));
    out->md5 = dup_or_null(bunny_json_get_string_or(file_obj, "full_file_md5", NULL));
    out->full_width = inkbunny_field_int(file_obj, "full_size_x", 0);
    out->full_height = inkbunny_field_int(file_obj, "full_size_y", 0);
    out->order = inkbunny_field_int(file_obj, "submission_file_order", 0);
}

static inkbunny_result_t parse_file_array(const cJSON *array, inkbunny_file_list_t *out) {
    out->items = NULL;
    out->count = 0;
    if (!array) {
        return INKBUNNY_OK;
    }
    if (!cJSON_IsArray(array)) {
        return INKBUNNY_ERR_PARSE;
    }

    size_t n = (size_t)cJSON_GetArraySize(array);
    if (n == 0) {
        return INKBUNNY_OK;
    }

    inkbunny_file_t *items = calloc(n, sizeof(inkbunny_file_t));
    if (!items) {
        return INKBUNNY_ERR_UNKNOWN;
    }

    size_t i = 0;
    const cJSON *item;
    cJSON_ArrayForEach(item, array) {
        parse_file(item, &items[i]);
        i++;
    }

    out->items = items;
    out->count = n;
    return INKBUNNY_OK;
}

static void parse_keyword(const cJSON *obj, inkbunny_keyword_t *out) {
    memset(out, 0, sizeof(*out));
    if (!obj) {
        return;
    }
    out->keyword_id = inkbunny_field_int64(obj, "keyword_id", 0);
    out->keyword_name = dup_or_null(bunny_json_get_string_or(obj, "keyword_name", NULL));
    out->contributed = inkbunny_field_bool_tf(obj, "contributed", false);
    out->submissions_count = inkbunny_field_int(obj, "submissions_count", 0);
}

static inkbunny_result_t parse_keyword_array(const cJSON *array, inkbunny_keyword_list_t *out) {
    out->items = NULL;
    out->count = 0;
    if (!array) {
        return INKBUNNY_OK;
    }
    if (!cJSON_IsArray(array)) {
        return INKBUNNY_ERR_PARSE;
    }

    size_t n = (size_t)cJSON_GetArraySize(array);
    if (n == 0) {
        return INKBUNNY_OK;
    }

    inkbunny_keyword_t *items = calloc(n, sizeof(inkbunny_keyword_t));
    if (!items) {
        return INKBUNNY_ERR_UNKNOWN;
    }

    size_t i = 0;
    const cJSON *item;
    cJSON_ArrayForEach(item, array) {
        parse_keyword(item, &items[i]);
        i++;
    }

    out->items = items;
    out->count = n;
    return INKBUNNY_OK;
}

static void parse_content_rating(const cJSON *obj, inkbunny_content_rating_t *out) {
    memset(out, 0, sizeof(*out));
    if (!obj) {
        return;
    }
    out->content_tag_id = inkbunny_field_int64(obj, "content_tag_id", 0);
    out->name = dup_or_null(bunny_json_get_string_or(obj, "name", NULL));
    out->description = dup_or_null(bunny_json_get_string_or(obj, "description", NULL));
    out->rating_id = inkbunny_field_int(obj, "rating_id", 0);
}

static inkbunny_result_t parse_content_rating_array(const cJSON *array, inkbunny_content_rating_list_t *out) {
    out->items = NULL;
    out->count = 0;
    if (!array) {
        return INKBUNNY_OK;
    }
    if (!cJSON_IsArray(array)) {
        return INKBUNNY_ERR_PARSE;
    }

    size_t n = (size_t)cJSON_GetArraySize(array);
    if (n == 0) {
        return INKBUNNY_OK;
    }

    inkbunny_content_rating_t *items = calloc(n, sizeof(inkbunny_content_rating_t));
    if (!items) {
        return INKBUNNY_ERR_UNKNOWN;
    }

    size_t i = 0;
    const cJSON *item;
    cJSON_ArrayForEach(item, array) {
        parse_content_rating(item, &items[i]);
        i++;
    }

    out->items = items;
    out->count = n;
    return INKBUNNY_OK;
}

static void parse_pool(const cJSON *obj, inkbunny_pool_t *out) {
    memset(out, 0, sizeof(*out));
    if (!obj) {
        return;
    }
    out->pool_id = inkbunny_field_int64(obj, "pool_id", 0);
    out->name = dup_or_null(bunny_json_get_string_or(obj, "name", NULL));
    out->description = dup_or_null(bunny_json_get_string_or(obj, "description", NULL));
    out->count = inkbunny_field_int(obj, "count", 0);
}

static inkbunny_result_t parse_pool_array(const cJSON *array, inkbunny_pool_list_t *out) {
    out->items = NULL;
    out->count = 0;
    if (!array) {
        return INKBUNNY_OK;
    }
    if (!cJSON_IsArray(array)) {
        return INKBUNNY_ERR_PARSE;
    }

    size_t n = (size_t)cJSON_GetArraySize(array);
    if (n == 0) {
        return INKBUNNY_OK;
    }

    inkbunny_pool_t *items = calloc(n, sizeof(inkbunny_pool_t));
    if (!items) {
        return INKBUNNY_ERR_UNKNOWN;
    }

    size_t i = 0;
    const cJSON *item;
    cJSON_ArrayForEach(item, array) {
        parse_pool(item, &items[i]);
        i++;
    }

    out->items = items;
    out->count = n;
    return INKBUNNY_OK;
}

inkbunny_result_t inkbunny_parse_submission(const cJSON *json, inkbunny_submission_t *out) {
    if (!json || !out) {
        return INKBUNNY_ERR_INVALID_ARG;
    }
    memset(out, 0, sizeof(*out));

    int64_t id = inkbunny_field_int64(json, "submission_id", -1);
    if (id < 0) {
        return INKBUNNY_ERR_PARSE;
    }
    out->submission_id = id;

    out->username = dup_or_null(bunny_json_get_string_or(json, "username", NULL));
    out->user_id = inkbunny_field_int64(json, "user_id", 0);
    out->title = dup_or_null(bunny_json_get_string_or(json, "title", NULL));
    out->description = dup_or_null(bunny_json_get_string_or(json, "description", NULL));
    out->rating_id = inkbunny_field_int(json, "rating_id", 0);
    out->rating_name = dup_or_null(bunny_json_get_string_or(json, "rating_name", NULL));

    parse_content_rating_array(cJSON_GetObjectItemCaseSensitive(json, "ratings"), &out->content_ratings);
    parse_keyword_array(cJSON_GetObjectItemCaseSensitive(json, "keywords"), &out->keywords);
    parse_file_array(cJSON_GetObjectItemCaseSensitive(json, "files"), &out->files);
    parse_pool_array(cJSON_GetObjectItemCaseSensitive(json, "pools"), &out->pools);

    out->thumbnail_url = dup_or_null(bunny_json_get_string_or(json, "thumbnail_url_large_noncustom", NULL));
    out->submission_type_id = inkbunny_field_int(json, "submission_type_id", 0);
    out->type_name = dup_or_null(bunny_json_get_string_or(json, "type_name", NULL));
    out->is_favorite = inkbunny_field_bool_tf(json, "favorite", false);
    out->favorites_count = inkbunny_field_int(json, "favorites_count", 0);
    out->comments_count = inkbunny_field_int(json, "comments_count", 0);
    out->views = inkbunny_field_int(json, "views", 0);
    out->created_at = dup_or_null(bunny_json_get_string_or(json, "create_datetime", NULL));

    return INKBUNNY_OK;
}

inkbunny_result_t inkbunny_parse_submission_array(const cJSON *json_array, inkbunny_submission_list_t *out) {
    if (!json_array || !out) {
        return INKBUNNY_ERR_INVALID_ARG;
    }
    if (!cJSON_IsArray(json_array)) {
        return INKBUNNY_ERR_PARSE;
    }
    memset(out, 0, sizeof(*out));

    size_t n = (size_t)cJSON_GetArraySize(json_array);
    if (n == 0) {
        return INKBUNNY_OK;
    }

    inkbunny_submission_t *items = calloc(n, sizeof(inkbunny_submission_t));
    if (!items) {
        return INKBUNNY_ERR_UNKNOWN;
    }

    size_t i = 0;
    const cJSON *item;
    cJSON_ArrayForEach(item, json_array) {
        inkbunny_result_t result = inkbunny_parse_submission(item, &items[i]);
        if (result != INKBUNNY_OK) {
            for (size_t j = 0; j < i; j++) {
                inkbunny_submission_free(&items[j]);
            }
            free(items);
            return result;
        }
        i++;
    }

    out->items = items;
    out->count = n;
    return INKBUNNY_OK;
}

void inkbunny_file_free(inkbunny_file_t *file) {
    if (!file) {
        return;
    }
    free(file->file_name);
    free(file->url_full);
    free(file->url_screen);
    free(file->url_preview);
    free(file->mimetype);
    free(file->md5);
    memset(file, 0, sizeof(*file));
}

void inkbunny_file_list_free(inkbunny_file_list_t *list) {
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        inkbunny_file_free(&list->items[i]);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

void inkbunny_keyword_free(inkbunny_keyword_t *keyword) {
    if (!keyword) {
        return;
    }
    free(keyword->keyword_name);
    memset(keyword, 0, sizeof(*keyword));
}

void inkbunny_keyword_list_free(inkbunny_keyword_list_t *list) {
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        inkbunny_keyword_free(&list->items[i]);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

void inkbunny_content_rating_free(inkbunny_content_rating_t *rating) {
    if (!rating) {
        return;
    }
    free(rating->name);
    free(rating->description);
    memset(rating, 0, sizeof(*rating));
}

void inkbunny_content_rating_list_free(inkbunny_content_rating_list_t *list) {
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        inkbunny_content_rating_free(&list->items[i]);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

void inkbunny_pool_free(inkbunny_pool_t *pool) {
    if (!pool) {
        return;
    }
    free(pool->name);
    free(pool->description);
    memset(pool, 0, sizeof(*pool));
}

void inkbunny_pool_list_free(inkbunny_pool_list_t *list) {
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        inkbunny_pool_free(&list->items[i]);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

void inkbunny_submission_free(inkbunny_submission_t *submission) {
    if (!submission) {
        return;
    }
    free(submission->username);
    free(submission->title);
    free(submission->description);
    free(submission->rating_name);
    inkbunny_content_rating_list_free(&submission->content_ratings);
    inkbunny_keyword_list_free(&submission->keywords);
    inkbunny_file_list_free(&submission->files);
    inkbunny_pool_list_free(&submission->pools);
    free(submission->thumbnail_url);
    free(submission->type_name);
    free(submission->created_at);
    memset(submission, 0, sizeof(*submission));
}

void inkbunny_submission_list_free(inkbunny_submission_list_t *list) {
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        inkbunny_submission_free(&list->items[i]);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}
