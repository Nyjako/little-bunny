/* timegm isn't standard C11 -- glibc only declares it when a sufficiently
 * permissive feature-test macro is requested. Must be defined before any
 * system header pulls in <features.h>. (strptime used to need _XOPEN_SOURCE
 * too, but seconds_until_due() below parses last_run_at with sscanf instead now
 * -- that format is always exactly "%Y-%m-%dT%H:%M:%S" (this app's own
 * output), so there's no real parsing to delegate to strptime for, and
 * sscanf is standard C with no glibc extension or feature-test-macro
 * dependency to worry about on any platform, MSVC included -- MSVC has no
 * strptime at all, with or without a feature-test macro.) */
#define _DEFAULT_SOURCE

#include "bunny_core/core.h"

#include <e621/client.h>
#include <goblin/cstr.h>
#include <goblin/dyn_array.h>
#include <inkbunny/client.h>

#include <ctype.h>
#include <stdbool.h>
#include <stdio.h>
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
 * loop below instead keeps paging until a page comes back empty. Neither
 * sync_e621_search nor sync_inkbunny_search caps the number of pages -- both
 * terminate purely on the site returning a short/empty page (see the
 * comments on each). */
#define BUNNY_CORE_SYNC_E621_PAGE_LIMIT 320

/* Used only to accumulate bunny_core_preview_search's results below --
 * file-local, like every GOBLIN_DYN_ARRAY_DECL instantiation in this
 * codebase (the macro expands to `static inline` functions, so there's no
 * link collision with libs/db's own identically-shaped bunny_db_post_array). */
GOBLIN_DYN_ARRAY_DECL(bunny_core_post, bunny_db_post_t)

/* Used only by parse_pool_references below, to accumulate matches before
 * handing the caller a plain array. */
GOBLIN_DYN_ARRAY_DECL(bunny_core_int64, int64_t)

/* timegm's Windows equivalent -- same signature/semantics (struct tm,
 * interpreted as UTC, converted to time_t), just a different name. */
#ifdef _WIN32
#define bunny_timegm _mkgmtime
#else
#define bunny_timegm timegm
#endif

/* <= 0 means due right now; otherwise the number of seconds remaining until
 * `search` becomes due. Feeds both search_is_due (the yes/no check every
 * sync pass actually needs) and bunny_core_sync_due_searches' own
 * "seconds_until_next_due" diagnostic stat (M28) -- computed once per search
 * either way, rather than duplicating this parsing in two places.
 *
 * default_interval_hours is only consulted when search->uses_default_interval
 * is set -- resolved once per bunny_core_sync_due_searches call (not once per
 * search) and passed down, since it's the same single row read regardless of
 * how many searches are being checked. */
static double seconds_until_due(const bunny_db_search_t *search, int default_interval_hours)
{
    if (!search->last_run_at) {
        return 0;
    }

    int year, month, day, hour, min, sec;
    if (sscanf(search->last_run_at, "%d-%d-%dT%d:%d:%d", &year, &month, &day, &hour, &min, &sec) != 6) {
        return 0; /* unparseable timestamp -- treat as due rather than getting stuck */
    }

    struct tm tm_last;
    memset(&tm_last, 0, sizeof(tm_last));
    tm_last.tm_year = year - 1900;
    tm_last.tm_mon = month - 1;
    tm_last.tm_mday = day;
    tm_last.tm_hour = hour;
    tm_last.tm_min = min;
    tm_last.tm_sec = sec;

    time_t last_run = bunny_timegm(&tm_last);
    int effective_interval_hours = search->uses_default_interval ? default_interval_hours : search->interval_hours;
    return difftime(last_run, time(NULL)) + effective_interval_hours * 3600.0;
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

/* Inkbunny's API has no e621-style bare "ext" field -- derive one from the
 * real file name's suffix (e.g. "full_12345_user_title.jpg" -> "jpg") so the
 * app's fileExt-gated media widget (post_detail_screen.dart's _buildMedia)
 * has something to key off of, same as e621's post->file.ext does. Returns
 * NULL (not a malloc'd empty string) when there's no '.' to split on, so
 * callers can free() unconditionally without a NULL check. */
static char *inkbunny_file_ext(const char *file_name)
{
    if (!file_name) {
        return NULL;
    }
    const char *dot = strrchr(file_name, '.');
    if (!dot || !dot[1]) {
        return NULL;
    }
    char *ext = goblin_copy_cstr(dot + 1);
    if (ext) {
        goblin_to_lower_cstr(ext);
    }
    return ext;
}

static bunny_core_result_t upsert_inkbunny_submission(bunny_db_t *db, const inkbunny_submission_t *submission, int64_t *out_post_id)
{
    flat_tag_list_t tags = flatten_inkbunny_keywords(submission);
    const inkbunny_file_t *file = submission->files.count > 0 ? &submission->files.items[0] : NULL;
    char *file_ext = file ? inkbunny_file_ext(file->file_name) : NULL;

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
    upsert.file_ext = file_ext;
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
    free(file_ext);

    return bunny_core_map_db_result(result);
}

/* Builds the "(i/N)" suffix used by the progress log lines below --
 * `position` is 1-based; 0 means "not applicable" (e.g. a single forced
 * sync via bunny_core_sync_search has no batch to report a position in). */
static void format_position_suffix(char *out, size_t out_size, int position, int total)
{
    if (position > 0) {
        snprintf(out, out_size, " (%d/%d)", position, total);
    } else {
        out[0] = '\0';
    }
}

/* Upserts every post in `posts` and links it to `search`, bumping `stats`,
 * `found_count`, and `new_count` (posts not already linked to this search
 * before this call) and queuing auto-favorite/upvote as needed -- shared by
 * the first-scan and incremental branches of sync_e621_search below. */
/* Batches the whole page into one transaction (and one db_mutex hold)
 * instead of one implicit auto-commit transaction (and one db_mutex
 * acquisition) per post. A page can have up to BUNNY_CORE_SYNC_E621_PAGE_LIMIT
 * (320) posts -- committing each individually meant up to 320 separate
 * fsync-backed commits per page. Under a long sync (many pages back-to-back,
 * no cap -- see the comment above sync_e621_search), that added up to
 * db_mutex rarely ever being free, which is what actually made routes like
 * GET /searches feel slow during a sync even though no single critical
 * section was ever individually long. One transaction per page cuts commit
 * count (and db_mutex acquisitions) by up to 320x with no behavior change. */
static void upsert_e621_search_page(bunny_core_t *core, const bunny_db_search_t *search, const e621_post_list_t *posts, bunny_core_sync_stats_t *stats, int *found_count, int *new_count)
{
    int64_t to_favorite[BUNNY_CORE_SYNC_E621_PAGE_LIMIT];
    size_t to_favorite_count = 0;
    int64_t to_upvote[BUNNY_CORE_SYNC_E621_PAGE_LIMIT];
    size_t to_upvote_count = 0;

    bunny_core_db_lock(core);
    bunny_db_begin_transaction(core->db);
    for (size_t i = 0; i < posts->count; i++) {
        int64_t post_id = 0;
        bool upserted_ok = upsert_e621_post(core->db, &posts->items[i], &post_id) == BUNNY_CORE_OK;
        bool was_new = false;
        if (upserted_ok) {
            bunny_db_search_add_result(core->db, search->id, post_id, &was_new);
        }
        if (upserted_ok) {
            if (search->auto_favorite) {
                to_favorite[to_favorite_count++] = post_id;
            }
            if (search->auto_upvote) {
                to_upvote[to_upvote_count++] = post_id;
            }
            if (stats) {
                stats->posts_upserted++;
            }
            (*found_count)++;
            if (was_new) {
                (*new_count)++;
            }
        }
    }
    bunny_db_commit_transaction(core->db);
    bunny_core_db_unlock(core);

    /* bunny_core_queue_favorite_add/queue_vote lock internally for their own
     * single write -- called outside the critical section above since
     * bunny_core_db_lock/unlock isn't re-entrant. */
    for (size_t i = 0; i < to_favorite_count; i++) {
        bunny_core_queue_favorite_add(core, to_favorite[i], search->auto_favorite_stars);
    }
    for (size_t i = 0; i < to_upvote_count; i++) {
        bunny_core_queue_vote(core, to_upvote[i], 1, false);
    }
}

/* e621's own API docs recommend against plain numeric `page=<N>` for
 * iterating a large result set -- posts can shift between pages if anything
 * is created/deleted on the site between requests, and page numbers above
 * 750 return an outright error. The `page=a<ID>`/`page=b<ID>` cursor form
 * has neither problem (and overrides any `order:` meta-tag, so it stays
 * correct by id regardless of the search's own sort order), so both the
 * first full scan and every later incremental sync use it exclusively --
 * there is no numeric-page pagination left in this function at all, and
 * deliberately no page-count cap either: both loops below terminate purely
 * on the site returning a short/empty page. `position`/`total` are only for
 * the progress log line -- see format_position_suffix above. */
/* sync_mutex is held for this entire function (acquired before the opening
 * "Starting/Checking" log line, released after the closing "Scanned" line)
 * -- see internal.h. This is what keeps the server from ever running more
 * than one site-facing sync at a time, whether triggered by the scheduler
 * or a manual request, and as a side effect makes two concurrent syncs of
 * the SAME search impossible rather than merely safe-but-redundant. */
static bunny_core_result_t sync_e621_search(bunny_core_t *core, const bunny_db_search_t *search, bunny_core_sync_stats_t *stats, int position, int total)
{
    bunny_core_sync_lock(core);

    char position_suffix[32];
    format_position_suffix(position_suffix, sizeof(position_suffix), position, total);

    bool is_first_sync = !search->last_run_at;
    bunny_core_log(core, "INFO", is_first_sync ? "Starting full scan for \"%s\"%s" : "Checking \"%s\" for updates%s", search->label, position_suffix);

    e621_client_t *client = bunny_core_build_e621_client(core);
    if (!client) {
        bunny_core_log(core, "ERROR", "Failed to build e621 client for \"%s\"", search->label);
        bunny_core_sync_unlock(core);
        return BUNNY_CORE_ERR_SITE;
    }

    int64_t max_id_seen = search->highest_synced_external_id;
    int found_count = 0;
    int new_count = 0;

    if (!search->initial_sync_done) {
        /* First scan: bare request (no page param -- newest first), then
         * walk backward via page=b<lowest_id_seen_so_far> until the site
         * signals "nothing older left" with a short page. */
        bool first_request = true;
        int64_t cursor = 0;
        for (;;) {
            e621_post_list_t posts;
            e621_result_t search_result = first_request ? e621_search_posts(client, search->query, 1, BUNNY_CORE_SYNC_E621_PAGE_LIMIT, &posts)
                                                          : e621_search_posts_before(client, search->query, cursor, BUNNY_CORE_SYNC_E621_PAGE_LIMIT, &posts);
            first_request = false;
            if (search_result != E621_OK) {
                bunny_core_log(core, "ERROR", "Scan of \"%s\" failed (e621 request error)", search->label);
                e621_client_destroy(client);
                bunny_core_sync_unlock(core);
                return BUNNY_CORE_ERR_SITE;
            }

            upsert_e621_search_page(core, search, &posts, stats, &found_count, &new_count);
            for (size_t i = 0; i < posts.count; i++) {
                int64_t id = posts.items[i].id;
                if (id > max_id_seen) {
                    max_id_seen = id;
                }
                if (cursor == 0 || id < cursor) {
                    cursor = id;
                }
            }

            bool last_page = posts.count < BUNNY_CORE_SYNC_E621_PAGE_LIMIT;
            e621_post_list_free(&posts);
            if (last_page) {
                break;
            }
        }
    } else {
        /* Incremental: only ask for posts newer than the highest one any
         * sync has seen so far, walking forward via
         * page=a<highest_id_seen_so_far> until a short page. */
        int64_t cursor = search->highest_synced_external_id;
        for (;;) {
            e621_post_list_t posts;
            e621_result_t search_result = e621_search_posts_after(client, search->query, cursor, BUNNY_CORE_SYNC_E621_PAGE_LIMIT, &posts);
            if (search_result != E621_OK) {
                bunny_core_log(core, "ERROR", "Scan of \"%s\" failed (e621 request error)", search->label);
                e621_client_destroy(client);
                bunny_core_sync_unlock(core);
                return BUNNY_CORE_ERR_SITE;
            }

            upsert_e621_search_page(core, search, &posts, stats, &found_count, &new_count);
            for (size_t i = 0; i < posts.count; i++) {
                int64_t id = posts.items[i].id;
                if (id > max_id_seen) {
                    max_id_seen = id;
                }
                if (id > cursor) {
                    cursor = id;
                }
            }

            bool last_page = posts.count < BUNNY_CORE_SYNC_E621_PAGE_LIMIT;
            e621_post_list_free(&posts);
            if (last_page) {
                break;
            }
        }
    }

    bunny_core_db_lock(core);
    bunny_db_search_update_sync_progress(core->db, search->id, max_id_seen);
    bunny_core_db_unlock(core);
    e621_client_destroy(client);
    bunny_core_log(core, "INFO", "Scanned \"%s\" -- found %d post(s), %d new", search->label, found_count, new_count);

    /* A pool search also gets its own order synced once per pass (M26) --
     * best-effort, a failure here (e.g. the pool itself got deleted) is
     * logged but doesn't fail the whole search sync, which already
     * succeeded above. */
    int64_t pool_id = 0;
    if (bunny_core_parse_pool_id_from_query(search->query, &pool_id) && bunny_core_sync_pool_order(core, pool_id) != BUNNY_CORE_OK) {
        bunny_core_log(core, "WARN", "Failed to sync pool order for \"%s\" (pool #%lld)", search->label, (long long)pool_id);
    }

    bunny_core_sync_unlock(core);
    return BUNNY_CORE_OK;
}

/* sync_mutex is held for this entire function -- see the identical note on
 * sync_e621_search above. */
static bunny_core_result_t sync_inkbunny_search(bunny_core_t *core, const bunny_db_search_t *search, bunny_core_sync_stats_t *stats, int position, int total)
{
    bunny_core_sync_lock(core);

    char position_suffix[32];
    format_position_suffix(position_suffix, sizeof(position_suffix), position, total);

    bool is_first_sync = !search->last_run_at;
    bunny_core_log(core, "INFO", is_first_sync ? "Starting full scan for \"%s\"%s" : "Checking \"%s\" for updates%s", search->label, position_suffix);

    inkbunny_client_t *client = bunny_core_build_inkbunny_client(core);
    if (!client) {
        bunny_core_log(core, "ERROR", "Failed to build Inkbunny client for \"%s\"", search->label);
        bunny_core_sync_unlock(core);
        return BUNNY_CORE_ERR_SITE;
    }

    int found_count = 0;
    int new_count = 0;

    /* A favorites search is just a search whose query happens to be this
     * exact sentinel (M27) -- same idea as e621's "pool:<id>" searches,
     * except the sentinel is a fixed literal rather than carrying data,
     * since it's always created by the app itself (never user-typed) once
     * an Inkbunny account exists. Inkbunny's search API has no
     * username-based equivalent of e621's "fav:<username>" tag --
     * favorited_by_user_id needs the numeric id of whoever's *currently
     * logged in*, resolved fresh here rather than baked into the query at
     * creation time, since re-resolving on every sync is cheap and avoids
     * ever going stale if the account changes. */
    char favorited_by_user_id[32];
    bool is_favorites_search = strcmp(search->query, "favorited_by:me") == 0;
    if (is_favorites_search) {
        snprintf(favorited_by_user_id, sizeof(favorited_by_user_id), "%lld", (long long)inkbunny_client_get_user_id(client));
    }

    /* Inkbunny has no confirmed id-cursor pagination like e621's a<ID>/b<ID>,
     * so this still walks plain numeric pages (newest first, since nothing
     * in this codebase sets a custom Inkbunny sort order) -- but stops as
     * soon as it hits a post already linked to this search from a previous
     * sync, since everything from there on (this page and all later pages)
     * was already synced last time. On a first-ever sync nothing is linked
     * yet, so this never triggers and the full walk runs as before. No
     * page-count cap, same reasoning as the e621 first scan above -- keeps
     * going until the site itself returns an empty page. */
    for (int page = 1;; page++) {
        inkbunny_search_params_t params;
        memset(&params, 0, sizeof(params));
        if (is_favorites_search) {
            params.favorited_by_user_id = favorited_by_user_id;
        } else {
            params.text = search->query;
        }
        params.page = page;

        inkbunny_submission_list_t submissions;
        inkbunny_result_t search_result = inkbunny_search(client, &params, &submissions);
        if (search_result != INKBUNNY_OK) {
            bunny_core_log(core, "ERROR", "Scan of \"%s\" failed (Inkbunny request error)", search->label);
            inkbunny_client_destroy(client);
            bunny_core_sync_unlock(core);
            return BUNNY_CORE_ERR_SITE;
        }

        if (submissions.count == 0) {
            inkbunny_submission_list_free(&submissions);
            break;
        }

        /* Batched into one transaction (and one db_mutex hold) for the whole
         * page instead of one implicit auto-commit transaction per
         * submission -- same reasoning as upsert_e621_search_page above. */
        bool reached_already_synced = false;
        int64_t *to_favorite = malloc(submissions.count * sizeof(int64_t));
        size_t to_favorite_count = 0;

        bunny_core_db_lock(core);
        bunny_db_begin_transaction(core->db);
        for (size_t i = 0; i < submissions.count; i++) {
            int64_t post_id = 0;
            bool upserted_ok = upsert_inkbunny_submission(core->db, &submissions.items[i], &post_id) == BUNNY_CORE_OK;
            bool already_linked = false;
            if (upserted_ok) {
                /* has_result (check) + add_result (act) must stay in the
                 * same critical section -- see "Remaining risk" in
                 * docs/architecture.md's M18 section for what this does and
                 * doesn't guarantee under concurrent syncs of the same search. */
                bunny_db_search_has_result(core->db, search->id, post_id, &already_linked);
                if (!already_linked) {
                    bunny_db_search_add_result(core->db, search->id, post_id, NULL);
                }
            }

            if (!upserted_ok) {
                continue;
            }
            found_count++;
            if (already_linked) {
                reached_already_synced = true;
                break;
            }

            new_count++;
            if (search->auto_favorite) {
                to_favorite[to_favorite_count++] = post_id;
            }
            if (stats) {
                stats->posts_upserted++;
            }
        }
        bunny_db_commit_transaction(core->db);
        bunny_core_db_unlock(core);

        /* bunny_core_queue_favorite_add locks internally -- called outside
         * the critical section above since bunny_core_db_lock/unlock isn't
         * re-entrant. */
        for (size_t i = 0; i < to_favorite_count; i++) {
            bunny_core_queue_favorite_add(core, to_favorite[i], -1);
        }
        free(to_favorite);
        inkbunny_submission_list_free(&submissions);
        if (reached_already_synced) {
            break;
        }
    }

    inkbunny_client_destroy(client);
    bunny_core_log(core, "INFO", "Scanned \"%s\" -- found %d post(s), %d new", search->label, found_count, new_count);
    bunny_core_sync_unlock(core);
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

        bunny_core_db_lock(core);
        bunny_core_result_t result = upsert_e621_post(core->db, &post, out_post_id);
        bunny_core_db_unlock(core);
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

    bunny_core_db_lock(core);
    bunny_core_result_t result = upsert_inkbunny_submission(core->db, &submission, out_post_id);
    bunny_core_db_unlock(core);
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
            bunny_core_db_lock(core);
            bool ok = upsert_e621_post(core->db, &posts.items[i], &post_id) == BUNNY_CORE_OK && bunny_db_post_get_by_id(core->db, post_id, &item) == BUNNY_DB_OK;
            bunny_core_db_unlock(core);
            if (ok) {
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
            bunny_core_db_lock(core);
            bool ok = upsert_inkbunny_submission(core->db, &submissions.items[i], &post_id) == BUNNY_CORE_OK && bunny_db_post_get_by_id(core->db, post_id, &item) == BUNNY_DB_OK;
            bunny_core_db_unlock(core);
            if (ok) {
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
        bunny_core_db_lock(core);
        bool ok = upsert_inkbunny_submission(core->db, &submissions.items[i], &post_id) == BUNNY_CORE_OK && bunny_db_post_get_by_id(core->db, post_id, &item) == BUNNY_DB_OK;
        bunny_core_db_unlock(core);
        if (ok) {
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
    free(info->description);
    free(info->referenced_pool_ids);
    memset(info, 0, sizeof(*info));
}

/* e621's own dtext convention for cross-referencing another pool from free
 * text (a pool's description, M26) -- the literal substring "pool #"
 * followed by one or more digits, however it's wrapped (plain text, inside
 * a "label":url link, mid-sentence, ...). Matches are returned in
 * first-seen order, duplicates included -- out_ids is NULL/out_count 0 for
 * no matches (including a NULL description), never an error, since "no
 * references" is the overwhelmingly common, entirely valid case. */
static void parse_pool_references(const char *description, int64_t **out_ids, size_t *out_count)
{
    *out_ids = NULL;
    *out_count = 0;
    if (!description) {
        return;
    }

    static const char *MARKER = "pool #";
    const size_t marker_len = 6; /* strlen("pool #") */

    bunny_core_int64_array arr;
    bunny_core_int64_array_init(&arr);

    const char *cursor = description;
    while ((cursor = strstr(cursor, MARKER)) != NULL) {
        cursor += marker_len;
        if (!isdigit((unsigned char)*cursor)) {
            continue; /* "pool #" without a number after it isn't a real reference */
        }
        int64_t id = 0;
        while (isdigit((unsigned char)*cursor)) {
            id = id * 10 + (*cursor - '0');
            cursor++;
        }
        bunny_core_int64_array_push(&arr, id); /* best-effort: a push failure here just drops one reference, not a real failure */
    }

    *out_ids = arr.items;
    *out_count = arr.count;
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
    out_info->description = pool.description ? goblin_copy_cstr(pool.description) : NULL;
    out_info->post_count = (int64_t)pool.post_count;
    parse_pool_references(pool.description, &out_info->referenced_pool_ids, &out_info->referenced_pool_id_count);
    e621_pool_free(&pool);
    return BUNNY_CORE_OK;
}

bunny_core_result_t bunny_core_sync_pool_order(bunny_core_t *core, int64_t pool_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }

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

    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_pool_set_post_positions(core->db, pool_id, pool.post_ids, pool.post_count);
    bunny_core_db_unlock(core);
    e621_pool_free(&pool);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_backfill_pool_positions_once(bunny_core_t *core)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }

    size_t status_slot;
    bunny_db_t *status_read_db = bunny_core_db_read_lock(core, &status_slot);
    bool already_done = false;
    bunny_db_result_t check_result = bunny_db_settings_get_pool_positions_backfilled(status_read_db, &already_done);
    bunny_core_db_read_unlock(core, status_slot);
    if (check_result != BUNNY_DB_OK) {
        return bunny_core_map_db_result(check_result);
    }
    if (already_done) {
        return BUNNY_CORE_OK;
    }

    bunny_db_int64_list_t pool_ids;
    memset(&pool_ids, 0, sizeof(pool_ids));
    size_t list_slot;
    bunny_db_t *list_read_db = bunny_core_db_read_lock(core, &list_slot);
    bunny_db_result_t list_result = bunny_db_list_distinct_pool_ids(list_read_db, &pool_ids);
    bunny_core_db_read_unlock(core, list_slot);
    if (list_result == BUNNY_DB_OK) {
        for (size_t i = 0; i < pool_ids.count; i++) {
            bunny_core_sync_pool_order(core, pool_ids.items[i]); /* best-effort -- one bad/deleted pool shouldn't stop the rest */
        }
        bunny_db_int64_list_free(&pool_ids);
    }

    bunny_core_db_lock(core);
    bunny_db_result_t set_result = bunny_db_settings_set_pool_positions_backfilled(core->db, true);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(set_result);
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
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t post_result = bunny_db_post_get_by_id(read_db, post_id, &post);
    bunny_core_db_read_unlock(core, slot);
    bunny_core_result_t lookup_result = bunny_core_map_db_result(post_result);
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
    bunny_core_db_lock(core);
    bunny_db_result_t list_result = bunny_db_search_list(core->db, &searches);
    int default_interval_hours = 24;
    bunny_db_settings_get_default_interval_hours(core->db, &default_interval_hours);
    bunny_core_db_unlock(core);
    if (list_result != BUNNY_DB_OK) {
        return bunny_core_map_db_result(list_result);
    }

    stats.seconds_until_next_due = -1;
    for (size_t i = 0; i < searches.count; i++) {
        const bunny_db_search_t *search = &searches.items[i]; /* searches is this call's own heap snapshot, safe to read lock-free across the sync call below */
        stats.searches_checked++;
        double remaining = seconds_until_due(search, default_interval_hours);
        if (remaining > 0) {
            if (stats.seconds_until_next_due < 0 || remaining < stats.seconds_until_next_due) {
                stats.seconds_until_next_due = remaining;
            }
            continue;
        }

        bunny_core_result_t sync_result = search->site == BUNNY_DB_SITE_E621 ? sync_e621_search(core, search, &stats, (int)(i + 1), (int)searches.count) : sync_inkbunny_search(core, search, &stats, (int)(i + 1), (int)searches.count);

        if (sync_result == BUNNY_CORE_OK) {
            stats.searches_synced++;
            bunny_core_db_lock(core);
            bunny_db_search_touch_last_run(core->db, search->id);
            bunny_core_db_unlock(core);
        }
    }

    bunny_db_search_list_free(&searches);
    if (out_stats) {
        *out_stats = stats;
    }
    return BUNNY_CORE_OK;
}

bunny_core_result_t bunny_core_sync_search(bunny_core_t *core, int64_t search_id, bunny_core_sync_stats_t *out_stats)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }

    bunny_db_search_list_t searches;
    bunny_core_db_lock(core);
    bunny_db_result_t list_result = bunny_db_search_list(core->db, &searches);
    bunny_core_db_unlock(core);
    if (list_result != BUNNY_DB_OK) {
        return bunny_core_map_db_result(list_result);
    }

    const bunny_db_search_t *search = NULL;
    for (size_t i = 0; i < searches.count; i++) {
        if (searches.items[i].id == search_id) {
            search = &searches.items[i];
            break;
        }
    }
    if (!search) {
        bunny_db_search_list_free(&searches);
        return BUNNY_CORE_ERR_NOT_FOUND;
    }

    bunny_core_sync_stats_t stats;
    memset(&stats, 0, sizeof(stats));
    stats.searches_checked = 1;

    bunny_core_result_t sync_result = search->site == BUNNY_DB_SITE_E621 ? sync_e621_search(core, search, &stats, 0, 0) : sync_inkbunny_search(core, search, &stats, 0, 0);
    if (sync_result == BUNNY_CORE_OK) {
        stats.searches_synced = 1;
        bunny_core_db_lock(core);
        bunny_db_search_touch_last_run(core->db, search_id);
        bunny_core_db_unlock(core);
    }

    bunny_db_search_list_free(&searches);
    if (out_stats) {
        *out_stats = stats;
    }
    return sync_result;
}
