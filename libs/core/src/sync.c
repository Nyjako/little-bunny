/* strptime/timegm aren't standard C11 -- glibc only declares them when a
 * sufficiently permissive feature-test macro is requested (timegm needs
 * _DEFAULT_SOURCE, not just _XOPEN_SOURCE). Must be defined before any
 * system header pulls in <features.h>. */
#define _DEFAULT_SOURCE
#define _XOPEN_SOURCE 700

#include "bunny_core/core.h"

#include <e621/client.h>
#include <inkbunny/client.h>

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "internal.h"

typedef struct
{
    const char **items;
    size_t count;
} flat_tag_list_t;

static bool search_is_due(const bunny_db_search_t *search)
{
    if (!search->last_run_at) {
        return true;
    }

    struct tm tm_last;
    memset(&tm_last, 0, sizeof(tm_last));
    if (!strptime(search->last_run_at, "%Y-%m-%dT%H:%M:%S", &tm_last)) {
        return true; /* unparseable timestamp -- treat as due rather than getting stuck */
    }

    time_t last_run = timegm(&tm_last);
    double hours_elapsed = difftime(time(NULL), last_run) / 3600.0;
    return hours_elapsed >= search->interval_hours;
}

static char *join_string_list(const e621_string_list_t *list)
{
    if (!list || list->count == 0) {
        return NULL;
    }
    size_t len = 0;
    for (size_t i = 0; i < list->count; i++) {
        len += strlen(list->items[i]) + 2;
    }
    char *out = malloc(len + 1);
    if (!out) {
        return NULL;
    }
    out[0] = '\0';
    for (size_t i = 0; i < list->count; i++) {
        strcat(out, list->items[i]);
        if (i + 1 < list->count) {
            strcat(out, ", ");
        }
    }
    return out;
}

static flat_tag_list_t flatten_e621_tags(const e621_post_t *post)
{
    const e621_string_list_t *lists[] = {
        &post->tags.general, &post->tags.artist, &post->tags.copyright, &post->tags.character, &post->tags.species, &post->tags.invalid, &post->tags.lore, &post->tags.meta,
    };
    size_t list_count = sizeof(lists) / sizeof(lists[0]);

    size_t total = 0;
    for (size_t i = 0; i < list_count; i++) {
        total += lists[i]->count;
    }

    flat_tag_list_t result = {0};
    if (total == 0) {
        return result;
    }

    const char **items = malloc(total * sizeof(char *));
    if (!items) {
        return result;
    }

    size_t j = 0;
    for (size_t i = 0; i < list_count; i++) {
        for (size_t k = 0; k < lists[i]->count; k++) {
            items[j++] = lists[i]->items[k];
        }
    }
    result.items = items;
    result.count = total;
    return result;
}

static flat_tag_list_t flatten_inkbunny_keywords(const inkbunny_submission_t *submission)
{
    flat_tag_list_t result = {0};
    if (submission->keywords.count == 0) {
        return result;
    }

    const char **items = malloc(submission->keywords.count * sizeof(char *));
    if (!items) {
        return result;
    }
    for (size_t i = 0; i < submission->keywords.count; i++) {
        items[i] = submission->keywords.items[i].keyword_name;
    }
    result.items = items;
    result.count = submission->keywords.count;
    return result;
}

static const char *e621_rating_to_text(e621_rating_t rating)
{
    switch (rating) {
        case E621_RATING_SAFE:
            return "s";
        case E621_RATING_QUESTIONABLE:
            return "q";
        case E621_RATING_EXPLICIT:
            return "e";
        default:
            return NULL;
    }
}

static bunny_core_result_t upsert_e621_post(bunny_db_t *db, const e621_post_t *post, int64_t *out_post_id)
{
    char *artist = join_string_list(&post->tags.artist);
    flat_tag_list_t tags = flatten_e621_tags(post);

    bunny_db_post_upsert_t upsert;
    memset(&upsert, 0, sizeof(upsert));
    upsert.site = BUNNY_DB_SITE_E621;
    upsert.external_id = post->id;
    upsert.artist = artist;
    upsert.description = post->description;
    upsert.rating = e621_rating_to_text(post->rating);
    upsert.score = post->score.total;
    upsert.fav_count = post->fav_count;
    upsert.comment_count = post->comment_count;
    upsert.file_url = post->file.url;
    upsert.file_ext = post->file.ext;
    upsert.file_md5 = post->file.md5;
    upsert.preview_url = post->preview.url;
    upsert.width = post->file.width;
    upsert.height = post->file.height;
    upsert.created_at_site = post->created_at;
    upsert.tags = tags.items;
    upsert.tag_count = tags.count;

    bunny_db_result_t result = bunny_db_post_upsert(db, &upsert, out_post_id);

    free(artist);
    free((void *)tags.items);

    return bunny_core_map_db_result(result);
}

static bunny_core_result_t upsert_inkbunny_submission(bunny_db_t *db, const inkbunny_submission_t *submission, int64_t *out_post_id)
{
    flat_tag_list_t tags = flatten_inkbunny_keywords(submission);
    const inkbunny_file_t *file = submission->files.count > 0 ? &submission->files.items[0] : NULL;

    bunny_db_post_upsert_t upsert;
    memset(&upsert, 0, sizeof(upsert));
    upsert.site = BUNNY_DB_SITE_INKBUNNY;
    upsert.external_id = submission->submission_id;
    upsert.artist = submission->username;
    upsert.title = submission->title;
    upsert.description = submission->description;
    upsert.rating = submission->rating_name;
    upsert.fav_count = submission->favorites_count;
    upsert.comment_count = submission->comments_count;
    upsert.file_url = file ? file->url_full : NULL;
    upsert.file_md5 = file ? file->md5 : NULL;
    upsert.preview_url = submission->thumbnail_url;
    upsert.width = file ? file->full_width : 0;
    upsert.height = file ? file->full_height : 0;
    upsert.created_at_site = submission->created_at;
    upsert.tags = tags.items;
    upsert.tag_count = tags.count;

    bunny_db_result_t result = bunny_db_post_upsert(db, &upsert, out_post_id);

    free((void *)tags.items);

    return bunny_core_map_db_result(result);
}

static bunny_core_result_t sync_e621_search(bunny_core_t *core, const bunny_db_search_t *search, bunny_core_sync_stats_t *stats)
{
    e621_client_t *client = bunny_core_build_e621_client(core);
    if (!client) {
        return BUNNY_CORE_ERR_SITE;
    }

    e621_post_list_t posts;
    e621_result_t search_result = e621_search_posts(client, search->query, 1, 0, &posts);
    e621_client_destroy(client);
    if (search_result != E621_OK) {
        return BUNNY_CORE_ERR_SITE;
    }

    for (size_t i = 0; i < posts.count; i++) {
        int64_t post_id = 0;
        if (upsert_e621_post(core->db, &posts.items[i], &post_id) == BUNNY_CORE_OK) {
            bunny_db_search_add_result(core->db, search->id, post_id);
            if (stats) {
                stats->posts_upserted++;
            }
        }
    }
    e621_post_list_free(&posts);
    return BUNNY_CORE_OK;
}

static bunny_core_result_t sync_inkbunny_search(bunny_core_t *core, const bunny_db_search_t *search, bunny_core_sync_stats_t *stats)
{
    inkbunny_client_t *client = bunny_core_build_inkbunny_client(core);
    if (!client) {
        return BUNNY_CORE_ERR_SITE;
    }

    inkbunny_search_params_t params;
    memset(&params, 0, sizeof(params));
    params.text = search->query;
    params.page = 1;

    inkbunny_submission_list_t submissions;
    inkbunny_result_t search_result = inkbunny_search(client, &params, &submissions);
    inkbunny_client_destroy(client);
    if (search_result != INKBUNNY_OK) {
        return BUNNY_CORE_ERR_SITE;
    }

    for (size_t i = 0; i < submissions.count; i++) {
        int64_t post_id = 0;
        if (upsert_inkbunny_submission(core->db, &submissions.items[i], &post_id) == BUNNY_CORE_OK) {
            bunny_db_search_add_result(core->db, search->id, post_id);
            if (stats) {
                stats->posts_upserted++;
            }
        }
    }
    inkbunny_submission_list_free(&submissions);
    return BUNNY_CORE_OK;
}

bunny_core_result_t bunny_core_sync_due_searches(bunny_core_t *core, bunny_core_sync_stats_t *out_stats)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }

    bunny_core_sync_stats_t stats;
    memset(&stats, 0, sizeof(stats));

    bunny_db_search_list_t searches;
    bunny_db_result_t list_result = bunny_db_search_list(core->db, &searches);
    if (list_result != BUNNY_DB_OK) {
        return bunny_core_map_db_result(list_result);
    }

    for (size_t i = 0; i < searches.count; i++) {
        const bunny_db_search_t *search = &searches.items[i];
        stats.searches_checked++;
        if (!search_is_due(search)) {
            continue;
        }

        bunny_core_result_t sync_result = search->site == BUNNY_DB_SITE_E621 ? sync_e621_search(core, search, &stats) : sync_inkbunny_search(core, search, &stats);

        if (sync_result == BUNNY_CORE_OK) {
            stats.searches_synced++;
            bunny_db_search_touch_last_run(core->db, search->id);
        }
    }

    bunny_db_search_list_free(&searches);
    if (out_stats) {
        *out_stats = stats;
    }
    return BUNNY_CORE_OK;
}
