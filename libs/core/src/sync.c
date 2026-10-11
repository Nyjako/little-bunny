/* strptime/timegm aren't standard C11 -- glibc only declares them when a
 * sufficiently permissive feature-test macro is requested (timegm needs
 * _DEFAULT_SOURCE, not just _XOPEN_SOURCE). Must be defined before any
 * system header pulls in <features.h>. */
#define _DEFAULT_SOURCE
#define _XOPEN_SOURCE 700

#include "bunny_core/core.h"

#include <e621/client.h>
#include <goblin/cstr.h>
#include <goblin/dyn_array.h>
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
    /* Parallel to items (same length as count) -- categories[i] is items[i]'s
     * e621 category, or NULL wholesale when there's no category info at all
     * (e.g. Inkbunny keywords, which have no category concept). */
    const char **categories;
} flat_tag_list_t;

/* e621's real API allows up to 320 posts/page; Inkbunny has no explicit
 * per-page limit param (the site's own implicit page size applies), so its
 * loop below instead keeps paging until a page comes back empty. Both loops
 * are capped at this many pages so one sync pass can't run unboundedly long
 * against a search matching an enormous number of posts. */
#define BUNNY_CORE_SYNC_E621_PAGE_LIMIT 320
#define BUNNY_CORE_SYNC_MAX_PAGES 20

/* Used only to accumulate bunny_core_preview_search's results below --
 * file-local, like every GOBLIN_DYN_ARRAY_DECL instantiation in this
 * codebase (the macro expands to `static inline` functions, so there's no
 * link collision with libs/db's own identically-shaped bunny_db_post_array). */
GOBLIN_DYN_ARRAY_DECL(bunny_core_post, bunny_db_post_t)

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
    /* Parallel to lists[] above -- the category every tag in lists[i] belongs
     * to, since that grouping is exactly e621's own per-tag category. */
    static const char *const category_names[] = {
        "general", "artist", "copyright", "character", "species", "invalid", "lore", "meta",
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
    const char **categories = malloc(total * sizeof(char *));
    if (!items || !categories) {
        free(items);
        free(categories);
        return result;
    }

    size_t j = 0;
    for (size_t i = 0; i < list_count; i++) {
        for (size_t k = 0; k < lists[i]->count; k++) {
            items[j] = lists[i]->items[k];
            categories[j] = category_names[i];
            j++;
        }
    }
    result.items = items;
    result.count = total;
    result.categories = categories;
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
    upsert.score_up = post->score.up;
    upsert.score_down = post->score.down;
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
    upsert.tag_categories = tags.categories;
    upsert.sources = (const char **)post->sources.items;
    upsert.source_count = post->sources.count;
    upsert.has_parent = post->relationships.has_parent;
    upsert.parent_external_id = post->relationships.parent_id;
    upsert.has_active_children = post->relationships.has_active_children;
    upsert.child_external_ids = post->relationships.children;
    upsert.child_count = post->relationships.child_count;
    upsert.pool_ids = post->pool_ids;
    upsert.pool_count = post->pool_count;
    upsert.sample_url = post->sample.url;

    bunny_db_result_t result = bunny_db_post_upsert(db, &upsert, out_post_id);
    /* The site's own "did I favorite this" signal is authoritative -- mirror
     * it locally so favorites made directly on the website (or before this
     * app existed) show up correctly here too, not just ones queued through
     * this app's own favorite button (M10.3). Additive only: never clears a
     * locally-recorded favorite just because this particular response says
     * false, since that would turn a simple "pull favorites in" into a full
     * two-way overwrite, which wasn't asked for. */
    if (result == BUNNY_DB_OK && post->is_favorited) {
        bunny_db_favorite_add(db, *out_post_id, -1);
    }

    free(artist);
    free((void *)tags.items);
    free((void *)tags.categories);

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
    upsert.sample_url = file ? file->url_screen : NULL;

    bunny_db_result_t result = bunny_db_post_upsert(db, &upsert, out_post_id);
    /* Same reasoning as upsert_e621_post's own mirror above (M10.3). */
    if (result == BUNNY_DB_OK && submission->is_favorite) {
        bunny_db_favorite_add(db, *out_post_id, -1);
    }

    free((void *)tags.items);

    return bunny_core_map_db_result(result);
}

static bunny_core_result_t sync_e621_search(bunny_core_t *core, const bunny_db_search_t *search, bunny_core_sync_stats_t *stats)
{
    e621_client_t *client = bunny_core_build_e621_client(core);
    if (!client) {
        return BUNNY_CORE_ERR_SITE;
    }

    for (int page = 1; page <= BUNNY_CORE_SYNC_MAX_PAGES; page++) {
        e621_post_list_t posts;
        e621_result_t search_result = e621_search_posts(client, search->query, page, BUNNY_CORE_SYNC_E621_PAGE_LIMIT, &posts);
        if (search_result != E621_OK) {
            e621_client_destroy(client);
            return BUNNY_CORE_ERR_SITE;
        }

        for (size_t i = 0; i < posts.count; i++) {
            int64_t post_id = 0;
            if (upsert_e621_post(core->db, &posts.items[i], &post_id) == BUNNY_CORE_OK) {
                bunny_db_search_add_result(core->db, search->id, post_id);
                if (search->auto_favorite) {
                    bunny_core_queue_favorite_add(core, post_id, search->auto_favorite_stars);
                }
                if (search->auto_upvote) {
                    bunny_core_queue_vote(core, post_id, 1, false);
                }
                if (stats) {
                    stats->posts_upserted++;
                }
            }
        }

        bool last_page = posts.count < BUNNY_CORE_SYNC_E621_PAGE_LIMIT;
        e621_post_list_free(&posts);
        if (last_page) {
            break;
        }
    }

    e621_client_destroy(client);
    return BUNNY_CORE_OK;
}

static bunny_core_result_t sync_inkbunny_search(bunny_core_t *core, const bunny_db_search_t *search, bunny_core_sync_stats_t *stats)
{
    inkbunny_client_t *client = bunny_core_build_inkbunny_client(core);
    if (!client) {
        return BUNNY_CORE_ERR_SITE;
    }

    /* Inkbunny's search has no explicit per-page limit param (unlike e621's),
     * so there's no "requested vs. returned count" signal for the last page
     * -- keep paging until one comes back empty instead. */
    for (int page = 1; page <= BUNNY_CORE_SYNC_MAX_PAGES; page++) {
        inkbunny_search_params_t params;
        memset(&params, 0, sizeof(params));
        params.text = search->query;
        params.page = page;

        inkbunny_submission_list_t submissions;
        inkbunny_result_t search_result = inkbunny_search(client, &params, &submissions);
        if (search_result != INKBUNNY_OK) {
            inkbunny_client_destroy(client);
            return BUNNY_CORE_ERR_SITE;
        }

        if (submissions.count == 0) {
            inkbunny_submission_list_free(&submissions);
            break;
        }

        for (size_t i = 0; i < submissions.count; i++) {
            int64_t post_id = 0;
            if (upsert_inkbunny_submission(core->db, &submissions.items[i], &post_id) == BUNNY_CORE_OK) {
                bunny_db_search_add_result(core->db, search->id, post_id);
                if (search->auto_favorite) {
                    bunny_core_queue_favorite_add(core, post_id, -1);
                }
                if (stats) {
                    stats->posts_upserted++;
                }
            }
        }
        inkbunny_submission_list_free(&submissions);
    }

    inkbunny_client_destroy(client);
    return BUNNY_CORE_OK;
}

bunny_core_result_t bunny_core_fetch_and_cache_post(bunny_core_t *core, bunny_db_site_t site, int64_t external_id, int64_t *out_post_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }

    if (site == BUNNY_DB_SITE_E621) {
        e621_client_t *client = bunny_core_build_e621_client(core);
        if (!client) {
            return BUNNY_CORE_ERR_SITE;
        }

        e621_post_t post;
        memset(&post, 0, sizeof(post));
        e621_result_t fetch_result = e621_get_post(client, external_id, &post);
        if (fetch_result != E621_OK) {
            e621_client_destroy(client);
            return BUNNY_CORE_ERR_SITE;
        }

        bunny_core_result_t result = upsert_e621_post(core->db, &post, out_post_id);
        e621_post_free(&post);
        e621_client_destroy(client);
        return result;
    }

    inkbunny_client_t *client = bunny_core_build_inkbunny_client(core);
    if (!client) {
        return BUNNY_CORE_ERR_SITE;
    }

    inkbunny_submission_t submission;
    memset(&submission, 0, sizeof(submission));
    inkbunny_result_t fetch_result = inkbunny_get_submission(client, external_id, &submission);
    if (fetch_result != INKBUNNY_OK) {
        inkbunny_client_destroy(client);
        return BUNNY_CORE_ERR_SITE;
    }

    bunny_core_result_t result = upsert_inkbunny_submission(core->db, &submission, out_post_id);
    inkbunny_submission_free(&submission);
    inkbunny_client_destroy(client);
    return result;
}

bunny_core_result_t bunny_core_preview_search(bunny_core_t *core, bunny_db_site_t site, const char *query, int page, bunny_db_post_list_t *out_list)
{
    if (!core || !query || !out_list || page < 1) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    bunny_core_post_array arr;
    bunny_core_post_array_init(&arr);

    if (site == BUNNY_DB_SITE_E621) {
        e621_client_t *client = bunny_core_build_e621_client(core);
        if (!client) {
            return BUNNY_CORE_ERR_SITE;
        }

        e621_post_list_t posts;
        e621_result_t search_result = e621_search_posts(client, query, page, BUNNY_CORE_SYNC_E621_PAGE_LIMIT, &posts);
        if (search_result != E621_OK) {
            e621_client_destroy(client);
            return BUNNY_CORE_ERR_SITE;
        }

        for (size_t i = 0; i < posts.count; i++) {
            int64_t post_id = 0;
            bunny_db_post_t item;
            memset(&item, 0, sizeof(item));
            if (upsert_e621_post(core->db, &posts.items[i], &post_id) == BUNNY_CORE_OK && bunny_db_post_get_by_id(core->db, post_id, &item) == BUNNY_DB_OK) {
                bunny_core_post_array_push(&arr, item);
            }
        }
        e621_post_list_free(&posts);
        e621_client_destroy(client);
    } else {
        inkbunny_client_t *client = bunny_core_build_inkbunny_client(core);
        if (!client) {
            return BUNNY_CORE_ERR_SITE;
        }

        inkbunny_search_params_t params;
        memset(&params, 0, sizeof(params));
        params.text = query;
        params.page = page;

        inkbunny_submission_list_t submissions;
        inkbunny_result_t search_result = inkbunny_search(client, &params, &submissions);
        if (search_result != INKBUNNY_OK) {
            inkbunny_client_destroy(client);
            return BUNNY_CORE_ERR_SITE;
        }

        for (size_t i = 0; i < submissions.count; i++) {
            int64_t post_id = 0;
            bunny_db_post_t item;
            memset(&item, 0, sizeof(item));
            if (upsert_inkbunny_submission(core->db, &submissions.items[i], &post_id) == BUNNY_CORE_OK && bunny_db_post_get_by_id(core->db, post_id, &item) == BUNNY_DB_OK) {
                bunny_core_post_array_push(&arr, item);
            }
        }
        inkbunny_submission_list_free(&submissions);
        inkbunny_client_destroy(client);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_CORE_OK;
}

bunny_core_result_t bunny_core_list_my_inkbunny_favorites(bunny_core_t *core, int page, bunny_db_post_list_t *out_list)
{
    if (!core || !out_list || page < 1) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    inkbunny_client_t *client = bunny_core_build_inkbunny_client(core);
    if (!client) {
        return BUNNY_CORE_ERR_SITE;
    }

    char user_id_text[32];
    snprintf(user_id_text, sizeof(user_id_text), "%lld", (long long)inkbunny_client_get_user_id(client));

    inkbunny_search_params_t params;
    memset(&params, 0, sizeof(params));
    params.favorited_by_user_id = user_id_text;
    params.page = page;

    inkbunny_submission_list_t submissions;
    inkbunny_result_t search_result = inkbunny_search(client, &params, &submissions);
    if (search_result != INKBUNNY_OK) {
        inkbunny_client_destroy(client);
        return BUNNY_CORE_ERR_SITE;
    }

    bunny_core_post_array arr;
    bunny_core_post_array_init(&arr);
    for (size_t i = 0; i < submissions.count; i++) {
        int64_t post_id = 0;
        bunny_db_post_t item;
        memset(&item, 0, sizeof(item));
        if (upsert_inkbunny_submission(core->db, &submissions.items[i], &post_id) == BUNNY_CORE_OK && bunny_db_post_get_by_id(core->db, post_id, &item) == BUNNY_DB_OK) {
            bunny_core_post_array_push(&arr, item);
        }
    }
    inkbunny_submission_list_free(&submissions);
    inkbunny_client_destroy(client);

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_CORE_OK;
}

void bunny_core_pool_info_free(bunny_core_pool_info_t *info)
{
    if (!info) {
        return;
    }
    free(info->name);
    memset(info, 0, sizeof(*info));
}

bunny_core_result_t bunny_core_fetch_pool(bunny_core_t *core, int64_t pool_id, bunny_core_pool_info_t *out_info)
{
    if (!core || !out_info) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    memset(out_info, 0, sizeof(*out_info));

    e621_client_t *client = bunny_core_build_e621_client(core);
    if (!client) {
        return BUNNY_CORE_ERR_SITE;
    }

    e621_pool_t pool;
    memset(&pool, 0, sizeof(pool));
    e621_result_t fetch_result = e621_get_pool(client, pool_id, &pool);
    e621_client_destroy(client);
    if (fetch_result != E621_OK) {
        return BUNNY_CORE_ERR_SITE;
    }

    out_info->id = pool.id;
    out_info->name = pool.name ? goblin_copy_cstr(pool.name) : NULL;
    out_info->post_count = (int64_t)pool.post_count;
    e621_pool_free(&pool);
    return BUNNY_CORE_OK;
}

void bunny_core_comment_list_free(bunny_core_comment_list_t *list)
{
    if (!list) {
        return;
    }
    for (size_t i = 0; i < list->count; i++) {
        free(list->items[i].creator_name);
        free(list->items[i].body);
        free(list->items[i].created_at);
    }
    free(list->items);
    memset(list, 0, sizeof(*list));
}

bunny_core_result_t bunny_core_list_comments(bunny_core_t *core, int64_t post_id, bunny_core_comment_list_t *out_list)
{
    if (!core || !out_list) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    bunny_db_post_t post;
    memset(&post, 0, sizeof(post));
    bunny_core_result_t lookup_result = bunny_core_map_db_result(bunny_db_post_get_by_id(core->db, post_id, &post));
    if (lookup_result != BUNNY_CORE_OK) {
        return lookup_result;
    }
    if (post.site != BUNNY_DB_SITE_E621) {
        bunny_db_post_free(&post);
        return BUNNY_CORE_ERR_SITE;
    }
    int64_t external_id = post.external_id;
    bunny_db_post_free(&post);

    e621_client_t *client = bunny_core_build_e621_client(core);
    if (!client) {
        return BUNNY_CORE_ERR_SITE;
    }

    e621_comment_list_t comments;
    memset(&comments, 0, sizeof(comments));
    e621_result_t fetch_result = e621_comment_list(client, external_id, &comments);
    e621_client_destroy(client);
    if (fetch_result != E621_OK) {
        return BUNNY_CORE_ERR_SITE;
    }

    bunny_core_comment_t *items = comments.count > 0 ? calloc(comments.count, sizeof(bunny_core_comment_t)) : NULL;
    if (comments.count > 0 && !items) {
        e621_comment_list_free(&comments);
        return BUNNY_CORE_ERR_UNKNOWN;
    }
    for (size_t i = 0; i < comments.count; i++) {
        items[i].id = comments.items[i].id;
        items[i].creator_name = comments.items[i].creator_name ? goblin_copy_cstr(comments.items[i].creator_name) : NULL;
        items[i].body = comments.items[i].body ? goblin_copy_cstr(comments.items[i].body) : NULL;
        items[i].created_at = comments.items[i].created_at ? goblin_copy_cstr(comments.items[i].created_at) : NULL;
    }
    out_list->items = items;
    out_list->count = comments.count;
    e621_comment_list_free(&comments);
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
