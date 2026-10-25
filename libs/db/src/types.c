#include "bunny_db/types.h"

#include <stdlib.h>
#include <string.h>

const char *bunny_db_site_to_string(bunny_db_site_t site)
{
    switch (site) {
        case BUNNY_DB_SITE_E621:
            return "e621";
        case BUNNY_DB_SITE_INKBUNNY:
            return "inkbunny";
        default:
            return "e621";
    }
}

void bunny_db_account_free(bunny_db_account_t *account)
{
    if (!account) {
        return;
    }
    free(account->username);
    free(account->secret);
    free(account->created_at);
    memset(account, 0, sizeof(*account));
}

void bunny_db_search_free(bunny_db_search_t *search)
{
    if (!search) {
        return;
    }
    free(search->label);
    free(search->query);
    free(search->created_at);
    free(search->last_run_at);
    free(search->last_viewed_at);
    memset(search, 0, sizeof(*search));
}

void bunny_db_search_list_free(bunny_db_search_list_t *list)
{
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        bunny_db_search_free(&list->items[i]);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

void bunny_db_group_free(bunny_db_group_t *group)
{
    if (!group) {
        return;
    }
    free(group->name);
    free(group->created_at);
    memset(group, 0, sizeof(*group));
}

void bunny_db_group_list_free(bunny_db_group_list_t *list)
{
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        bunny_db_group_free(&list->items[i]);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

void bunny_db_post_free(bunny_db_post_t *post)
{
    if (!post) {
        return;
    }
    free(post->artist);
    free(post->title);
    free(post->description);
    free(post->rating);
    free(post->file_url);
    free(post->file_ext);
    free(post->file_md5);
    free(post->preview_url);
    free(post->created_at_site);
    free(post->cached_at);
    free(post->sample_url);
    memset(post, 0, sizeof(*post));
}

void bunny_db_post_list_free(bunny_db_post_list_t *list)
{
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        bunny_db_post_free(&list->items[i]);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

void bunny_db_tag_stat_free(bunny_db_tag_stat_t *stat)
{
    if (!stat) {
        return;
    }
    free(stat->name);
    memset(stat, 0, sizeof(*stat));
}

void bunny_db_tag_stat_list_free(bunny_db_tag_stat_list_t *list)
{
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        bunny_db_tag_stat_free(&list->items[i]);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

void bunny_db_post_tag_free(bunny_db_post_tag_t *tag)
{
    if (!tag) {
        return;
    }
    free(tag->name);
    free(tag->category);
    memset(tag, 0, sizeof(*tag));
}

void bunny_db_post_tag_list_free(bunny_db_post_tag_list_t *list)
{
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        bunny_db_post_tag_free(&list->items[i]);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

void bunny_db_string_list_free(bunny_db_string_list_t *list)
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

void bunny_db_int64_list_free(bunny_db_int64_list_t *list)
{
    if (!list) {
        return;
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

void bunny_db_post_relationships_free(bunny_db_post_relationships_t *relationships)
{
    if (!relationships) {
        return;
    }
    bunny_db_int64_list_free(&relationships->children);
    memset(relationships, 0, sizeof(*relationships));
}

const char *bunny_db_action_type_to_string(bunny_db_action_type_t action_type)
{
    switch (action_type) {
        case BUNNY_DB_ACTION_FAVORITE_ADD:
            return "favorite_add";
        case BUNNY_DB_ACTION_FAVORITE_REMOVE:
            return "favorite_remove";
        case BUNNY_DB_ACTION_VOTE:
            return "vote";
        case BUNNY_DB_ACTION_COMMENT:
            return "comment";
        default:
            return "favorite_add";
    }
}

void bunny_db_action_free(bunny_db_action_t *action)
{
    if (!action) {
        return;
    }
    free(action->payload);
    free(action->created_at);
    free(action->attempted_at);
    free(action->error_message);
    memset(action, 0, sizeof(*action));
}

void bunny_db_action_list_free(bunny_db_action_list_t *list)
{
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        bunny_db_action_free(&list->items[i]);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}
