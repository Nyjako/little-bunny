#include "bunny_core/core.h"

#include <e621/client.h>
#include <goblin/cstr.h>

#include <stdlib.h>
#include <string.h>

#include "internal.h"

static char *dup_or_null(const char *s)
{
    return s ? goblin_copy_cstr(s) : NULL;
}

static bunny_core_tag_category_t map_tag_category(e621_tag_category_t category)
{
    switch (category) {
        case E621_TAG_CATEGORY_GENERAL:
            return BUNNY_CORE_TAG_CATEGORY_GENERAL;
        case E621_TAG_CATEGORY_ARTIST:
            return BUNNY_CORE_TAG_CATEGORY_ARTIST;
        case E621_TAG_CATEGORY_COPYRIGHT:
            return BUNNY_CORE_TAG_CATEGORY_COPYRIGHT;
        case E621_TAG_CATEGORY_CHARACTER:
            return BUNNY_CORE_TAG_CATEGORY_CHARACTER;
        case E621_TAG_CATEGORY_SPECIES:
            return BUNNY_CORE_TAG_CATEGORY_SPECIES;
        case E621_TAG_CATEGORY_INVALID:
            return BUNNY_CORE_TAG_CATEGORY_INVALID;
        case E621_TAG_CATEGORY_LORE:
            return BUNNY_CORE_TAG_CATEGORY_LORE;
        case E621_TAG_CATEGORY_META:
            return BUNNY_CORE_TAG_CATEGORY_META;
        default:
            return BUNNY_CORE_TAG_CATEGORY_UNKNOWN;
    }
}

static void copy_string_list(const e621_string_list_t *src, bunny_db_string_list_t *dst)
{
    dst->items = NULL;
    dst->count = 0;
    if (src->count == 0) {
        return;
    }
    dst->items = calloc(src->count, sizeof(char *));
    if (!dst->items) {
        return;
    }
    for (size_t i = 0; i < src->count; i++) {
        dst->items[i] = goblin_copy_cstr(src->items[i]);
    }
    dst->count = src->count;
}

static void map_tag(const e621_tag_t *src, bunny_core_tag_t *dst)
{
    dst->id = src->id;
    dst->name = dup_or_null(src->name);
    dst->post_count = src->post_count;
    dst->category = map_tag_category(src->category);
    dst->related_tags = dup_or_null(src->related_tags);
    dst->is_locked = src->is_locked;
    dst->created_at = dup_or_null(src->created_at);
    dst->updated_at = dup_or_null(src->updated_at);
}

static void map_tag_alias(const e621_tag_alias_t *src, bunny_core_tag_alias_t *dst)
{
    dst->id = src->id;
    dst->antecedent_name = dup_or_null(src->antecedent_name);
    dst->consequent_name = dup_or_null(src->consequent_name);
    dst->status = dup_or_null(src->status);
    dst->post_count = src->post_count;
}

static void map_tag_implication(const e621_tag_implication_t *src, bunny_core_tag_implication_t *dst)
{
    dst->id = src->id;
    dst->antecedent_name = dup_or_null(src->antecedent_name);
    dst->consequent_name = dup_or_null(src->consequent_name);
    dst->status = dup_or_null(src->status);
}

void bunny_core_tag_list_free(bunny_core_tag_list_t *list)
{
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        free(list->items[i].name);
        free(list->items[i].related_tags);
        free(list->items[i].created_at);
        free(list->items[i].updated_at);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

void bunny_core_wiki_page_free(bunny_core_wiki_page_t *page)
{
    if (!page) {
        return;
    }
    free(page->title);
    free(page->body);
    for (size_t i = 0; i < page->other_names.count; i++) {
        free(page->other_names.items[i]);
    }
    free(page->other_names.items);
    free(page->created_at);
    free(page->updated_at);
    memset(page, 0, sizeof(*page));
}

void bunny_core_tag_alias_list_free(bunny_core_tag_alias_list_t *list)
{
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        free(list->items[i].antecedent_name);
        free(list->items[i].consequent_name);
        free(list->items[i].status);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

void bunny_core_tag_implication_list_free(bunny_core_tag_implication_list_t *list)
{
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        free(list->items[i].antecedent_name);
        free(list->items[i].consequent_name);
        free(list->items[i].status);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

bunny_core_result_t bunny_core_search_tags(bunny_core_t *core, const char *name_matches, int limit, bunny_core_tag_list_t *out_list)
{
    if (!core || !out_list) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    e621_client_t *client = bunny_core_build_e621_client(core);
    if (!client) {
        return BUNNY_CORE_ERR_SITE;
    }

    e621_tag_list_t tags;
    e621_result_t result = e621_search_tags(client, name_matches, limit, &tags);
    e621_client_destroy(client);
    if (result != E621_OK) {
        return BUNNY_CORE_ERR_SITE;
    }

    if (tags.count > 0) {
        out_list->items = calloc(tags.count, sizeof(bunny_core_tag_t));
        if (!out_list->items) {
            e621_tag_list_free(&tags);
            return BUNNY_CORE_ERR_UNKNOWN;
        }
        for (size_t i = 0; i < tags.count; i++) {
            map_tag(&tags.items[i], &out_list->items[i]);
        }
        out_list->count = tags.count;
    }
    e621_tag_list_free(&tags);
    return BUNNY_CORE_OK;
}

bunny_core_result_t bunny_core_get_wiki_page(bunny_core_t *core, const char *title, bunny_core_wiki_page_t *out_page)
{
    if (!core || !title || !out_page) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    memset(out_page, 0, sizeof(*out_page));

    e621_client_t *client = bunny_core_build_e621_client(core);
    if (!client) {
        return BUNNY_CORE_ERR_SITE;
    }

    e621_wiki_page_t page;
    e621_result_t result = e621_get_wiki_page(client, title, &page);
    e621_client_destroy(client);
    if (result == E621_ERR_NOT_FOUND) {
        return BUNNY_CORE_ERR_NOT_FOUND;
    }
    if (result != E621_OK) {
        return BUNNY_CORE_ERR_SITE;
    }

    out_page->id = page.id;
    out_page->title = dup_or_null(page.title);
    out_page->body = dup_or_null(page.body);
    copy_string_list(&page.other_names, &out_page->other_names);
    out_page->is_locked = page.is_locked;
    out_page->created_at = dup_or_null(page.created_at);
    out_page->updated_at = dup_or_null(page.updated_at);
    e621_wiki_page_free(&page);
    return BUNNY_CORE_OK;
}

bunny_core_result_t bunny_core_search_tag_aliases(bunny_core_t *core, const char *name_matches, int limit, bunny_core_tag_alias_list_t *out_list)
{
    if (!core || !out_list) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    e621_client_t *client = bunny_core_build_e621_client(core);
    if (!client) {
        return BUNNY_CORE_ERR_SITE;
    }

    e621_tag_alias_list_t aliases;
    e621_result_t result = e621_search_tag_aliases(client, name_matches, limit, &aliases);
    e621_client_destroy(client);
    if (result != E621_OK) {
        return BUNNY_CORE_ERR_SITE;
    }

    if (aliases.count > 0) {
        out_list->items = calloc(aliases.count, sizeof(bunny_core_tag_alias_t));
        if (!out_list->items) {
            e621_tag_alias_list_free(&aliases);
            return BUNNY_CORE_ERR_UNKNOWN;
        }
        for (size_t i = 0; i < aliases.count; i++) {
            map_tag_alias(&aliases.items[i], &out_list->items[i]);
        }
        out_list->count = aliases.count;
    }
    e621_tag_alias_list_free(&aliases);
    return BUNNY_CORE_OK;
}

bunny_core_result_t bunny_core_search_tag_implications(bunny_core_t *core, const char *name_matches, int limit, bunny_core_tag_implication_list_t *out_list)
{
    if (!core || !out_list) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    e621_client_t *client = bunny_core_build_e621_client(core);
    if (!client) {
        return BUNNY_CORE_ERR_SITE;
    }

    e621_tag_implication_list_t implications;
    e621_result_t result = e621_search_tag_implications(client, name_matches, limit, &implications);
    e621_client_destroy(client);
    if (result != E621_OK) {
        return BUNNY_CORE_ERR_SITE;
    }

    if (implications.count > 0) {
        out_list->items = calloc(implications.count, sizeof(bunny_core_tag_implication_t));
        if (!out_list->items) {
            e621_tag_implication_list_free(&implications);
            return BUNNY_CORE_ERR_UNKNOWN;
        }
        for (size_t i = 0; i < implications.count; i++) {
            map_tag_implication(&implications.items[i], &out_list->items[i]);
        }
        out_list->count = implications.count;
    }
    e621_tag_implication_list_free(&implications);
    return BUNNY_CORE_OK;
}
