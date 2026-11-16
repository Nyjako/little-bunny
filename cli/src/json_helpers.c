#include "json_helpers.h"

static void add_optional_string(cJSON *object, const char *key, const char *value)
{
    if (value) {
        cJSON_AddStringToObject(object, key, value);
    } else {
        cJSON_AddNullToObject(object, key);
    }
}

cJSON *bunny_cli_post_to_json(const bunny_db_post_t *post)
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

cJSON *bunny_cli_post_list_to_json(const bunny_db_post_list_t *list)
{
    cJSON *array = cJSON_CreateArray();
    for (size_t i = 0; i < list->count; i++) {
        cJSON_AddItemToArray(array, bunny_cli_post_to_json(&list->items[i]));
    }
    return array;
}

cJSON *bunny_cli_pool_info_to_json(const bunny_core_pool_info_t *info)
{
    cJSON *json = cJSON_CreateObject();
    cJSON_AddNumberToObject(json, "id", (double)info->id);
    add_optional_string(json, "name", info->name);
    add_optional_string(json, "description", info->description);
    cJSON_AddNumberToObject(json, "post_count", (double)info->post_count);

    cJSON *referenced = cJSON_CreateArray();
    for (size_t i = 0; i < info->referenced_pool_id_count; i++) {
        cJSON_AddItemToArray(referenced, cJSON_CreateNumber((double)info->referenced_pool_ids[i]));
    }
    cJSON_AddItemToObject(json, "referenced_pool_ids", referenced);

    return json;
}

cJSON *bunny_cli_string_list_to_json(const bunny_db_string_list_t *list)
{
    cJSON *array = cJSON_CreateArray();
    for (size_t i = 0; i < list->count; i++) {
        cJSON_AddItemToArray(array, cJSON_CreateString(list->items[i]));
    }
    return array;
}

cJSON *bunny_cli_download_queue_item_to_json(const bunny_db_download_queue_item_t *item)
{
    cJSON *json = cJSON_CreateObject();
    cJSON_AddNumberToObject(json, "id", (double)item->id);
    cJSON_AddNumberToObject(json, "post_id", (double)item->post_id);
    cJSON_AddStringToObject(json, "status", bunny_db_download_queue_status_to_string(item->status));
    add_optional_string(json, "failure_reason", item->failure_reason);
    cJSON_AddStringToObject(json, "created_at", item->created_at);
    cJSON_AddNumberToObject(json, "pool_id", (double)item->pool_id);
    add_optional_string(json, "pool_name", item->pool_name);
    cJSON_AddNumberToObject(json, "pool_page", item->pool_page);
    return json;
}

cJSON *bunny_cli_download_queue_list_to_json(const bunny_db_download_queue_list_t *list)
{
    cJSON *array = cJSON_CreateArray();
    for (size_t i = 0; i < list->count; i++) {
        cJSON_AddItemToArray(array, bunny_cli_download_queue_item_to_json(&list->items[i]));
    }
    return array;
}
