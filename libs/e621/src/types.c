#include "e621/types.h"

#include <goblin/cstr.h>

#include <stdlib.h>
#include <string.h>

#include "internal.h"

static char *dup_or_null(const char *s)
{
    return s ? goblin_copy_cstr(s) : NULL;
}

static e621_result_t parse_string_array(const cJSON *array, e621_string_list_t *out)
{
    out->items = NULL;
    out->count = 0;

    if (!array) {
        return E621_OK; /* absent => empty, not an error */
    }
    if (!cJSON_IsArray(array)) {
        return E621_ERR_PARSE;
    }

    size_t n = (size_t)cJSON_GetArraySize(array);
    if (n == 0) {
        return E621_OK;
    }

    char **items = calloc(n, sizeof(char *));
    if (!items) {
        return E621_ERR_UNKNOWN;
    }

    size_t i = 0;
    const cJSON *item;
    cJSON_ArrayForEach(item, array)
    {
        if (!cJSON_IsString(item) || !item->valuestring) {
            for (size_t j = 0; j < i; j++) {
                free(items[j]);
            }
            free(items);
            return E621_ERR_PARSE;
        }
        items[i] = goblin_copy_cstr(item->valuestring);
        if (!items[i]) {
            for (size_t j = 0; j < i; j++) {
                free(items[j]);
            }
            free(items);
            return E621_ERR_UNKNOWN;
        }
        i++;
    }

    out->items = items;
    out->count = n;
    return E621_OK;
}

static e621_result_t parse_int64_array(const cJSON *array, int64_t **out_items, size_t *out_count)
{
    *out_items = NULL;
    *out_count = 0;

    if (!array || !cJSON_IsArray(array)) {
        return E621_OK;
    }

    size_t n = (size_t)cJSON_GetArraySize(array);
    if (n == 0) {
        return E621_OK;
    }

    int64_t *items = calloc(n, sizeof(int64_t));
    if (!items) {
        return E621_ERR_UNKNOWN;
    }

    size_t i = 0;
    const cJSON *item;
    cJSON_ArrayForEach(item, array)
    {
        if (!cJSON_IsNumber(item)) {
            free(items);
            return E621_ERR_PARSE;
        }
        items[i++] = (int64_t)item->valuedouble;
    }

    *out_items = items;
    *out_count = n;
    return E621_OK;
}

static void parse_file(const cJSON *file_obj, e621_file_t *out)
{
    memset(out, 0, sizeof(*out));
    if (!file_obj) {
        return;
    }
    out->url = dup_or_null(bunny_json_get_string_or(file_obj, "url", NULL));
    out->ext = dup_or_null(bunny_json_get_string_or(file_obj, "ext", NULL));
    out->md5 = dup_or_null(bunny_json_get_string_or(file_obj, "md5", NULL));
    out->width = bunny_json_get_int_or(file_obj, "width", 0);
    out->height = bunny_json_get_int_or(file_obj, "height", 0);

    int64_t size = 0;
    bunny_json_get_int64(file_obj, "size", &size);
    out->size = size;
}

static void parse_score(const cJSON *score_obj, e621_score_t *out)
{
    out->up = bunny_json_get_int_or(score_obj, "up", 0);
    out->down = bunny_json_get_int_or(score_obj, "down", 0);
    out->total = bunny_json_get_int_or(score_obj, "total", 0);
}

static e621_rating_t parse_rating(const char *rating)
{
    if (!rating) {
        return E621_RATING_UNKNOWN;
    }
    if (strcmp(rating, "s") == 0) {
        return E621_RATING_SAFE;
    }
    if (strcmp(rating, "q") == 0) {
        return E621_RATING_QUESTIONABLE;
    }
    if (strcmp(rating, "e") == 0) {
        return E621_RATING_EXPLICIT;
    }
    return E621_RATING_UNKNOWN;
}

static e621_pool_category_t parse_pool_category(const char *category)
{
    if (!category) {
        return E621_POOL_CATEGORY_UNKNOWN;
    }
    if (strcmp(category, "series") == 0) {
        return E621_POOL_CATEGORY_SERIES;
    }
    if (strcmp(category, "collection") == 0) {
        return E621_POOL_CATEGORY_COLLECTION;
    }
    return E621_POOL_CATEGORY_UNKNOWN;
}

static void parse_relationships(const cJSON *relationships_obj, e621_relationships_t *out)
{
    memset(out, 0, sizeof(*out));
    if (!relationships_obj) {
        return;
    }

    int64_t parent_id = 0;
    if (bunny_json_get_int64(relationships_obj, "parent_id", &parent_id) == BUNNY_JSON_OK) {
        out->has_parent = true;
        out->parent_id = parent_id;
    }

    out->has_children = bunny_json_get_bool_or(relationships_obj, "has_children", false);
    out->has_active_children = bunny_json_get_bool_or(relationships_obj, "has_active_children", false);

    parse_int64_array(cJSON_GetObjectItemCaseSensitive(relationships_obj, "children"), &out->children, &out->child_count);
}

e621_result_t e621_parse_post(const cJSON *json, e621_post_t *out)
{
    if (!json || !out) {
        return E621_ERR_INVALID_ARG;
    }
    memset(out, 0, sizeof(*out));

    int64_t id = 0;
    if (bunny_json_get_int64(json, "id", &id) != BUNNY_JSON_OK) {
        return E621_ERR_PARSE;
    }
    out->id = id;

    out->created_at = dup_or_null(bunny_json_get_string_or(json, "created_at", NULL));

    parse_file(cJSON_GetObjectItemCaseSensitive(json, "file"), &out->file);
    parse_file(cJSON_GetObjectItemCaseSensitive(json, "preview"), &out->preview);
    parse_file(cJSON_GetObjectItemCaseSensitive(json, "sample"), &out->sample);

    parse_score(cJSON_GetObjectItemCaseSensitive(json, "score"), &out->score);

    out->fav_count = bunny_json_get_int_or(json, "fav_count", 0);
    out->is_favorited = bunny_json_get_bool_or(json, "is_favorited", false);
    out->rating = parse_rating(bunny_json_get_string_or(json, "rating", NULL));

    cJSON *tags_obj = cJSON_GetObjectItemCaseSensitive(json, "tags");
    if (tags_obj) {
        parse_string_array(cJSON_GetObjectItemCaseSensitive(tags_obj, "general"), &out->tags.general);
        parse_string_array(cJSON_GetObjectItemCaseSensitive(tags_obj, "artist"), &out->tags.artist);
        parse_string_array(cJSON_GetObjectItemCaseSensitive(tags_obj, "copyright"), &out->tags.copyright);
        parse_string_array(cJSON_GetObjectItemCaseSensitive(tags_obj, "character"), &out->tags.character);
        parse_string_array(cJSON_GetObjectItemCaseSensitive(tags_obj, "species"), &out->tags.species);
        parse_string_array(cJSON_GetObjectItemCaseSensitive(tags_obj, "invalid"), &out->tags.invalid);
        parse_string_array(cJSON_GetObjectItemCaseSensitive(tags_obj, "lore"), &out->tags.lore);
        parse_string_array(cJSON_GetObjectItemCaseSensitive(tags_obj, "meta"), &out->tags.meta);
    }

    parse_string_array(cJSON_GetObjectItemCaseSensitive(json, "sources"), &out->sources);

    out->description = dup_or_null(bunny_json_get_string_or(json, "description", NULL));
    out->comment_count = bunny_json_get_int_or(json, "comment_count", 0);

    parse_int64_array(cJSON_GetObjectItemCaseSensitive(json, "pools"), &out->pool_ids, &out->pool_count);

    parse_relationships(cJSON_GetObjectItemCaseSensitive(json, "relationships"), &out->relationships);

    return E621_OK;
}

e621_result_t e621_parse_post_array(const cJSON *json_array, e621_post_list_t *out)
{
    if (!json_array || !out) {
        return E621_ERR_INVALID_ARG;
    }
    if (!cJSON_IsArray(json_array)) {
        return E621_ERR_PARSE;
    }
    memset(out, 0, sizeof(*out));

    size_t n = (size_t)cJSON_GetArraySize(json_array);
    if (n == 0) {
        return E621_OK;
    }

    e621_post_t *items = calloc(n, sizeof(e621_post_t));
    if (!items) {
        return E621_ERR_UNKNOWN;
    }

    size_t i = 0;
    const cJSON *item;
    cJSON_ArrayForEach(item, json_array)
    {
        e621_result_t result = e621_parse_post(item, &items[i]);
        if (result != E621_OK) {
            for (size_t j = 0; j < i; j++) {
                e621_post_free(&items[j]);
            }
            free(items);
            return result;
        }
        i++;
    }

    out->items = items;
    out->count = n;
    return E621_OK;
}

e621_result_t e621_parse_comment(const cJSON *json, e621_comment_t *out)
{
    if (!json || !out) {
        return E621_ERR_INVALID_ARG;
    }
    memset(out, 0, sizeof(*out));

    int64_t id = 0;
    if (bunny_json_get_int64(json, "id", &id) != BUNNY_JSON_OK) {
        return E621_ERR_PARSE;
    }
    out->id = id;

    int64_t post_id = 0;
    bunny_json_get_int64(json, "post_id", &post_id);
    out->post_id = post_id;

    out->creator_name = dup_or_null(bunny_json_get_string_or(json, "creator_name", NULL));
    out->body = dup_or_null(bunny_json_get_string_or(json, "body", NULL));
    out->created_at = dup_or_null(bunny_json_get_string_or(json, "created_at", NULL));

    return E621_OK;
}

e621_result_t e621_parse_comment_array(const cJSON *json_array, e621_comment_list_t *out)
{
    if (!json_array || !out) {
        return E621_ERR_INVALID_ARG;
    }
    if (!cJSON_IsArray(json_array)) {
        return E621_ERR_PARSE;
    }
    memset(out, 0, sizeof(*out));

    size_t n = (size_t)cJSON_GetArraySize(json_array);
    if (n == 0) {
        return E621_OK;
    }

    e621_comment_t *items = calloc(n, sizeof(e621_comment_t));
    if (!items) {
        return E621_ERR_UNKNOWN;
    }

    size_t i = 0;
    const cJSON *item;
    cJSON_ArrayForEach(item, json_array)
    {
        e621_result_t result = e621_parse_comment(item, &items[i]);
        if (result != E621_OK) {
            for (size_t j = 0; j < i; j++) {
                e621_comment_free(&items[j]);
            }
            free(items);
            return result;
        }
        i++;
    }

    out->items = items;
    out->count = n;
    return E621_OK;
}

e621_result_t e621_parse_pool(const cJSON *json, e621_pool_t *out)
{
    if (!json || !out) {
        return E621_ERR_INVALID_ARG;
    }
    memset(out, 0, sizeof(*out));

    int64_t id = 0;
    if (bunny_json_get_int64(json, "id", &id) != BUNNY_JSON_OK) {
        return E621_ERR_PARSE;
    }
    out->id = id;

    out->name = dup_or_null(bunny_json_get_string_or(json, "name", NULL));
    out->description = dup_or_null(bunny_json_get_string_or(json, "description", NULL));
    out->created_at = dup_or_null(bunny_json_get_string_or(json, "created_at", NULL));
    out->updated_at = dup_or_null(bunny_json_get_string_or(json, "updated_at", NULL));

    int64_t creator_id = 0;
    bunny_json_get_int64(json, "creator_id", &creator_id);
    out->creator_id = creator_id;

    out->creator_name = dup_or_null(bunny_json_get_string_or(json, "creator_name", NULL));
    out->is_active = bunny_json_get_bool_or(json, "is_active", false);
    out->category = parse_pool_category(bunny_json_get_string_or(json, "category", NULL));

    parse_int64_array(cJSON_GetObjectItemCaseSensitive(json, "post_ids"), &out->post_ids, &out->post_count);

    return E621_OK;
}

/* e621's tags.json "category" field -- numeric codes matching the same
 * groupings e621_tags_t already buckets post tags into by name (general/
 * artist/copyright/character/species/invalid/lore/meta). 2 is unused on
 * e621's side; everything else unrecognized maps to UNKNOWN. */
static e621_tag_category_t parse_tag_category(int category)
{
    switch (category) {
        case 0:
            return E621_TAG_CATEGORY_GENERAL;
        case 1:
            return E621_TAG_CATEGORY_ARTIST;
        case 3:
            return E621_TAG_CATEGORY_COPYRIGHT;
        case 4:
            return E621_TAG_CATEGORY_CHARACTER;
        case 5:
            return E621_TAG_CATEGORY_SPECIES;
        case 6:
            return E621_TAG_CATEGORY_INVALID;
        case 7:
            return E621_TAG_CATEGORY_META;
        case 8:
            return E621_TAG_CATEGORY_LORE;
        default:
            return E621_TAG_CATEGORY_UNKNOWN;
    }
}

e621_result_t e621_parse_tag(const cJSON *json, e621_tag_t *out)
{
    if (!json || !out) {
        return E621_ERR_INVALID_ARG;
    }
    memset(out, 0, sizeof(*out));

    int64_t id = 0;
    if (bunny_json_get_int64(json, "id", &id) != BUNNY_JSON_OK) {
        return E621_ERR_PARSE;
    }
    out->id = id;

    out->name = dup_or_null(bunny_json_get_string_or(json, "name", NULL));
    out->post_count = bunny_json_get_int_or(json, "post_count", 0);
    out->category = parse_tag_category(bunny_json_get_int_or(json, "category", -1));
    out->related_tags = dup_or_null(bunny_json_get_string_or(json, "related_tags", NULL));
    out->is_locked = bunny_json_get_bool_or(json, "is_locked", false);
    out->created_at = dup_or_null(bunny_json_get_string_or(json, "created_at", NULL));
    out->updated_at = dup_or_null(bunny_json_get_string_or(json, "updated_at", NULL));

    return E621_OK;
}

e621_result_t e621_parse_tag_array(const cJSON *json_array, e621_tag_list_t *out)
{
    if (!json_array || !out) {
        return E621_ERR_INVALID_ARG;
    }
    if (!cJSON_IsArray(json_array)) {
        return E621_ERR_PARSE;
    }
    memset(out, 0, sizeof(*out));

    size_t n = (size_t)cJSON_GetArraySize(json_array);
    if (n == 0) {
        return E621_OK;
    }

    e621_tag_t *items = calloc(n, sizeof(e621_tag_t));
    if (!items) {
        return E621_ERR_UNKNOWN;
    }

    size_t i = 0;
    const cJSON *item;
    cJSON_ArrayForEach(item, json_array)
    {
        e621_result_t result = e621_parse_tag(item, &items[i]);
        if (result != E621_OK) {
            for (size_t j = 0; j < i; j++) {
                e621_tag_free(&items[j]);
            }
            free(items);
            return result;
        }
        i++;
    }

    out->items = items;
    out->count = n;
    return E621_OK;
}

e621_result_t e621_parse_wiki_page(const cJSON *json, e621_wiki_page_t *out)
{
    if (!json || !out) {
        return E621_ERR_INVALID_ARG;
    }
    memset(out, 0, sizeof(*out));

    int64_t id = 0;
    if (bunny_json_get_int64(json, "id", &id) != BUNNY_JSON_OK) {
        return E621_ERR_PARSE;
    }
    out->id = id;

    out->title = dup_or_null(bunny_json_get_string_or(json, "title", NULL));
    out->body = dup_or_null(bunny_json_get_string_or(json, "body", NULL));
    parse_string_array(cJSON_GetObjectItemCaseSensitive(json, "other_names"), &out->other_names);
    out->is_locked = bunny_json_get_bool_or(json, "is_locked", false);
    out->created_at = dup_or_null(bunny_json_get_string_or(json, "created_at", NULL));
    out->updated_at = dup_or_null(bunny_json_get_string_or(json, "updated_at", NULL));

    return E621_OK;
}

e621_result_t e621_parse_tag_alias(const cJSON *json, e621_tag_alias_t *out)
{
    if (!json || !out) {
        return E621_ERR_INVALID_ARG;
    }
    memset(out, 0, sizeof(*out));

    int64_t id = 0;
    if (bunny_json_get_int64(json, "id", &id) != BUNNY_JSON_OK) {
        return E621_ERR_PARSE;
    }
    out->id = id;

    out->antecedent_name = dup_or_null(bunny_json_get_string_or(json, "antecedent_name", NULL));
    out->consequent_name = dup_or_null(bunny_json_get_string_or(json, "consequent_name", NULL));
    out->status = dup_or_null(bunny_json_get_string_or(json, "status", NULL));
    out->post_count = bunny_json_get_int_or(json, "post_count", 0);

    return E621_OK;
}

e621_result_t e621_parse_tag_alias_array(const cJSON *json_array, e621_tag_alias_list_t *out)
{
    if (!json_array || !out) {
        return E621_ERR_INVALID_ARG;
    }
    if (!cJSON_IsArray(json_array)) {
        return E621_ERR_PARSE;
    }
    memset(out, 0, sizeof(*out));

    size_t n = (size_t)cJSON_GetArraySize(json_array);
    if (n == 0) {
        return E621_OK;
    }

    e621_tag_alias_t *items = calloc(n, sizeof(e621_tag_alias_t));
    if (!items) {
        return E621_ERR_UNKNOWN;
    }

    size_t i = 0;
    const cJSON *item;
    cJSON_ArrayForEach(item, json_array)
    {
        e621_result_t result = e621_parse_tag_alias(item, &items[i]);
        if (result != E621_OK) {
            for (size_t j = 0; j < i; j++) {
                e621_tag_alias_free(&items[j]);
            }
            free(items);
            return result;
        }
        i++;
    }

    out->items = items;
    out->count = n;
    return E621_OK;
}

e621_result_t e621_parse_tag_implication(const cJSON *json, e621_tag_implication_t *out)
{
    if (!json || !out) {
        return E621_ERR_INVALID_ARG;
    }
    memset(out, 0, sizeof(*out));

    int64_t id = 0;
    if (bunny_json_get_int64(json, "id", &id) != BUNNY_JSON_OK) {
        return E621_ERR_PARSE;
    }
    out->id = id;

    out->antecedent_name = dup_or_null(bunny_json_get_string_or(json, "antecedent_name", NULL));
    out->consequent_name = dup_or_null(bunny_json_get_string_or(json, "consequent_name", NULL));
    out->status = dup_or_null(bunny_json_get_string_or(json, "status", NULL));

    return E621_OK;
}

e621_result_t e621_parse_tag_implication_array(const cJSON *json_array, e621_tag_implication_list_t *out)
{
    if (!json_array || !out) {
        return E621_ERR_INVALID_ARG;
    }
    if (!cJSON_IsArray(json_array)) {
        return E621_ERR_PARSE;
    }
    memset(out, 0, sizeof(*out));

    size_t n = (size_t)cJSON_GetArraySize(json_array);
    if (n == 0) {
        return E621_OK;
    }

    e621_tag_implication_t *items = calloc(n, sizeof(e621_tag_implication_t));
    if (!items) {
        return E621_ERR_UNKNOWN;
    }

    size_t i = 0;
    const cJSON *item;
    cJSON_ArrayForEach(item, json_array)
    {
        e621_result_t result = e621_parse_tag_implication(item, &items[i]);
        if (result != E621_OK) {
            for (size_t j = 0; j < i; j++) {
                e621_tag_implication_free(&items[j]);
            }
            free(items);
            return result;
        }
        i++;
    }

    out->items = items;
    out->count = n;
    return E621_OK;
}

void e621_string_list_free(e621_string_list_t *list)
{
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        free(list->items[i]);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

void e621_file_free(e621_file_t *file)
{
    if (!file) {
        return;
    }
    free(file->url);
    free(file->ext);
    free(file->md5);
    file->url = NULL;
    file->ext = NULL;
    file->md5 = NULL;
}

void e621_post_free(e621_post_t *post)
{
    if (!post) {
        return;
    }
    free(post->created_at);
    e621_file_free(&post->file);
    e621_file_free(&post->preview);
    e621_file_free(&post->sample);
    e621_string_list_free(&post->tags.general);
    e621_string_list_free(&post->tags.artist);
    e621_string_list_free(&post->tags.copyright);
    e621_string_list_free(&post->tags.character);
    e621_string_list_free(&post->tags.species);
    e621_string_list_free(&post->tags.invalid);
    e621_string_list_free(&post->tags.lore);
    e621_string_list_free(&post->tags.meta);
    e621_string_list_free(&post->sources);
    free(post->description);
    free(post->pool_ids);
    free(post->relationships.children);
    memset(post, 0, sizeof(*post));
}

void e621_pool_free(e621_pool_t *pool)
{
    if (!pool) {
        return;
    }
    free(pool->name);
    free(pool->description);
    free(pool->created_at);
    free(pool->updated_at);
    free(pool->creator_name);
    free(pool->post_ids);
    memset(pool, 0, sizeof(*pool));
}

void e621_post_list_free(e621_post_list_t *list)
{
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        e621_post_free(&list->items[i]);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

void e621_comment_free(e621_comment_t *comment)
{
    if (!comment) {
        return;
    }
    free(comment->creator_name);
    free(comment->body);
    free(comment->created_at);
    memset(comment, 0, sizeof(*comment));
}

void e621_comment_list_free(e621_comment_list_t *list)
{
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        e621_comment_free(&list->items[i]);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

void e621_tag_free(e621_tag_t *tag)
{
    if (!tag) {
        return;
    }
    free(tag->name);
    free(tag->related_tags);
    free(tag->created_at);
    free(tag->updated_at);
    memset(tag, 0, sizeof(*tag));
}

void e621_tag_list_free(e621_tag_list_t *list)
{
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        e621_tag_free(&list->items[i]);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

void e621_wiki_page_free(e621_wiki_page_t *page)
{
    if (!page) {
        return;
    }
    free(page->title);
    free(page->body);
    e621_string_list_free(&page->other_names);
    free(page->created_at);
    free(page->updated_at);
    memset(page, 0, sizeof(*page));
}

void e621_tag_alias_free(e621_tag_alias_t *alias)
{
    if (!alias) {
        return;
    }
    free(alias->antecedent_name);
    free(alias->consequent_name);
    free(alias->status);
    memset(alias, 0, sizeof(*alias));
}

void e621_tag_alias_list_free(e621_tag_alias_list_t *list)
{
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        e621_tag_alias_free(&list->items[i]);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

void e621_tag_implication_free(e621_tag_implication_t *implication)
{
    if (!implication) {
        return;
    }
    free(implication->antecedent_name);
    free(implication->consequent_name);
    free(implication->status);
    memset(implication, 0, sizeof(*implication));
}

void e621_tag_implication_list_free(e621_tag_implication_list_t *list)
{
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        e621_tag_implication_free(&list->items[i]);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}
