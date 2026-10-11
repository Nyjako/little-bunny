#ifndef BUNNY_DB_DB_H
#define BUNNY_DB_DB_H

#include <stdbool.h>
#include <stdint.h>

#include "bunny_db/error.h"
#include "bunny_db/types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct bunny_db bunny_db_t;

/* path may be a filesystem path or ":memory:" for an in-process/test database.
 * Applies the schema (CREATE TABLE IF NOT EXISTS ...) on every open, so this
 * is safe to call against an existing database. */
bunny_db_result_t bunny_db_open(const char *path, bunny_db_t **out_db);
void bunny_db_close(bunny_db_t *db);

/* --- Accounts ---------------------------------------------------------------
 * One account per site (e621 API key, or Inkbunny username/password). Stored
 * as plain text: the server needs to read these unattended to run scheduled
 * syncs, so there's no passphrase-gated encryption layer here. App-lock
 * (password/PIN/fingerprint), if used, is a separate per-device client
 * concern (M7) with no relationship to this storage -- see architecture.md.
 * Setting an account again for the same site replaces it (upsert). */

bunny_db_result_t bunny_db_account_set(bunny_db_t *db, bunny_db_site_t site, const char *username, const char *secret);
bunny_db_result_t bunny_db_account_get(bunny_db_t *db, bunny_db_site_t site, bunny_db_account_t *out_account);
bunny_db_result_t bunny_db_account_delete(bunny_db_t *db, bunny_db_site_t site);

/* --- Searches ------------------------------------------------------------ */

bunny_db_result_t bunny_db_search_create(bunny_db_t *db, bunny_db_site_t site, const char *label, const char *query, int interval_hours, const bunny_db_search_options_t *options, int64_t *out_id);
bunny_db_result_t bunny_db_search_delete(bunny_db_t *db, int64_t search_id);
bunny_db_result_t bunny_db_search_list(bunny_db_t *db, bunny_db_search_list_t *out_list);
bunny_db_result_t bunny_db_search_touch_last_run(bunny_db_t *db, int64_t search_id);

/* Pin/unpin, toggled directly from the searches list row rather than
 * through the full edit form (M14.1) -- a dedicated setter rather than a
 * fourth bunny_db_search_options_t field, same reasoning as
 * bunny_db_search_touch_last_run already being its own function. */
bunny_db_result_t bunny_db_search_set_pinned(bunny_db_t *db, int64_t search_id, bool pinned);

/* Updates a search's editable fields in place (M9.7.2) -- replaces the
 * narrower bunny_db_search_set_auto_favorite, whose only caller (the
 * searches-list quick-toggle icon) was removed in favor of a full edit
 * screen. The site itself is not editable (not a param here). */
bunny_db_result_t bunny_db_search_update(bunny_db_t *db, int64_t search_id, const char *label, const char *query, int interval_hours, const bunny_db_search_options_t *options);

/* --- Posts cache ----------------------------------------------------------
 * Upserts are keyed on (site, external_id): calling this again for a post
 * already cached updates it in place rather than duplicating it. */

typedef struct
{
    bunny_db_site_t site;
    int64_t external_id;
    const char *artist;      /* may be NULL */
    const char *title;       /* may be NULL */
    const char *description; /* may be NULL */
    const char *rating;      /* may be NULL */
    int score;
    int score_up;   /* 0 for Inkbunny -- no vote concept there */
    int score_down; /* 0 for Inkbunny -- no vote concept there */
    int fav_count;
    int comment_count;
    const char *file_url;    /* may be NULL */
    const char *file_ext;    /* may be NULL */
    const char *file_md5;    /* may be NULL */
    const char *preview_url; /* may be NULL */
    int width;
    int height;
    const char *created_at_site; /* may be NULL */
    const char **tags;           /* may be NULL */
    size_t tag_count;
    /* Parallel to tags (same length as tag_count) -- tag_categories[i] is
     * tags[i]'s category, or NULL if uncategorized (always NULL for
     * Inkbunny keywords, which have no category concept). May be NULL
     * wholesale if no category info is available at all. */
    const char **tag_categories;
    const char **sources; /* may be NULL; order is preserved */
    size_t source_count;
    /* e621 parent/child/pool membership (site's own external ids) -- always
     * left at these zero-initialized defaults for Inkbunny, which has none
     * of this. */
    bool has_parent;
    int64_t parent_external_id; /* valid only when has_parent */
    bool has_active_children;
    const int64_t *child_external_ids; /* may be NULL */
    size_t child_count;
    const int64_t *pool_ids; /* may be NULL */
    size_t pool_count;
    const char *sample_url; /* medium-quality variant (e621's "sample", Inkbunny's "screen"); may be NULL */
} bunny_db_post_upsert_t;

bunny_db_result_t bunny_db_post_upsert(bunny_db_t *db, const bunny_db_post_upsert_t *post, int64_t *out_id);
bunny_db_result_t bunny_db_post_get(bunny_db_t *db, bunny_db_site_t site, int64_t external_id, bunny_db_post_t *out_post);

/* Same as bunny_db_post_get, but keyed on the local db id rather than
 * (site, external_id) -- what the action queue below has to work with, since
 * it stores the local id (matching bunny_db_favorite_add/download_record's
 * own convention). */
bunny_db_result_t bunny_db_post_get_by_id(bunny_db_t *db, int64_t post_id, bunny_db_post_t *out_post);

/* Associates a cached post with a search's result set (e.g. after running that
 * search against the site). Idempotent: re-adding the same pair is a no-op. */
bunny_db_result_t bunny_db_search_add_result(bunny_db_t *db, int64_t search_id, int64_t post_id);
bunny_db_result_t bunny_db_search_list_posts(bunny_db_t *db, int64_t search_id, bool unseen_only, bunny_db_post_list_t *out_list);

/* A post's tags with their categories, for a post detail view's sectioned
 * tag display (Artists/Characters/Copyrights/Species/General/Meta for e621;
 * a single uncategorized group for Inkbunny, whose keywords have no
 * category concept at all). */
bunny_db_result_t bunny_db_post_get_tags_by_category(bunny_db_t *db, int64_t post_id, bunny_db_post_tag_list_t *out_list);

/* A post's source URLs, in the site's own order (see post_sources' schema
 * comment). Empty for a post with none (e.g. every Inkbunny submission --
 * no such field there). */
bunny_db_result_t bunny_db_post_get_sources(bunny_db_t *db, int64_t post_id, bunny_db_string_list_t *out_list);

/* A post's parent/child relationships (e621 only -- see bunny_db_post_relationships_t's
 * doc comment). A post with no row in post_relationships (never had a parent or active
 * children) returns BUNNY_DB_OK with every field at its zero/empty default, not
 * BUNNY_DB_ERR_NOT_FOUND -- "no relationships" is a normal state, not a missing one. */
bunny_db_result_t bunny_db_post_get_relationships(bunny_db_t *db, int64_t post_id, bunny_db_post_relationships_t *out_relationships);

/* The e621 pool ids a post belongs to (empty for Inkbunny, or an e621 post in
 * no pools). Same "empty is OK, not NOT_FOUND" rule as the relationships read above. */
bunny_db_result_t bunny_db_post_get_pool_ids(bunny_db_t *db, int64_t post_id, bunny_db_int64_list_t *out_list);

/* --- Seen state (global per post, not per search) ------------------------- */

bunny_db_result_t bunny_db_post_mark_seen(bunny_db_t *db, int64_t post_id);
bunny_db_result_t bunny_db_count_unseen(bunny_db_t *db, int64_t *out_count);

/* Marks every post currently linked to `search_id` as seen in one call --
 * the bulk counterpart to bunny_db_post_mark_seen, for a post grid's
 * "mark all as seen" action. Posts already seen, or linked to other
 * searches too, are unaffected either way. */
bunny_db_result_t bunny_db_search_mark_all_seen(bunny_db_t *db, int64_t search_id);

/* --- Favorites mirror ------------------------------------------------------
 * A local cache of what's favorited, so the app doesn't have to round-trip to
 * the site to show favorite state. Does not itself call any site API. */

bunny_db_result_t bunny_db_favorite_add(bunny_db_t *db, int64_t post_id, int stars /* -1 if not applicable */);
bunny_db_result_t bunny_db_favorite_remove(bunny_db_t *db, int64_t post_id);
bunny_db_result_t bunny_db_favorite_list(bunny_db_t *db, bunny_db_post_list_t *out_list);

/* --- Votes mirror (M9.7.1) ---------------------------------------------------
 * A local cache of the caller's own most recently *successfully sent* vote
 * direction -- e621 only (Inkbunny has no vote API). e621's post-listing API
 * never returns "did I vote, and which way," so this is the only source of
 * truth for it; does not itself call any site API. */

bunny_db_result_t bunny_db_vote_set(bunny_db_t *db, int64_t post_id, int score /* -1 or 1 */);

/* --- Tag blacklist (M13.3) ---------------------------------------------------
 * A per-site list of exact tag names -- not foreign-keyed into tags(id),
 * since a tag someone wants to blacklist may never have been synced
 * locally. bunny_db_search_list_posts (below) excludes any post carrying a
 * blacklisted tag; bunny_core_preview_search's underlying post-listing
 * query is a separate function and is deliberately left unaffected, so
 * tag/pool browsing never hides anything by default. */

bunny_db_result_t bunny_db_blacklist_list(bunny_db_t *db, bunny_db_site_t site, bunny_db_string_list_t *out_list);
bunny_db_result_t bunny_db_blacklist_add(bunny_db_t *db, bunny_db_site_t site, const char *tag);
bunny_db_result_t bunny_db_blacklist_remove(bunny_db_t *db, bunny_db_site_t site, const char *tag);

/* --- Downloads -------------------------------------------------------------- */

bunny_db_result_t bunny_db_download_record(bunny_db_t *db, int64_t post_id, const char *file_path, const char *checksum_md5, bool verified, int64_t *out_id);
bunny_db_result_t bunny_db_download_list_for_post(bunny_db_t *db, int64_t post_id, bunny_db_download_list_t *out_list);

/* --- Tag stats -------------------------------------------------------------- */

/* Tags of currently-favorited posts on `site`, ordered by how many favorited
 * posts carry them, descending. Feeds the "most liked/favorited tags" feature
 * (M10.2). Scoped to `site` the same way bunny_db_tag_autocomplete already
 * is -- `tags` is UNIQUE(site, name), so an unscoped query would conflate
 * e.g. e621's "wolf" and Inkbunny's "wolf" into indistinguishable rows. */
bunny_db_result_t bunny_db_top_favorited_tags(bunny_db_t *db, bunny_db_site_t site, int limit, bunny_db_tag_stat_list_t *out_list);

/* Same ranking, but across every synced post on `site`, not just favorited
 * ones (M14.4) -- feeds the Tag Stats screen's "All" view, alongside
 * bunny_db_top_favorited_tags's existing "Favorites" view. */
bunny_db_result_t bunny_db_top_used_tags(bunny_db_t *db, bunny_db_site_t site, int limit, bunny_db_tag_stat_list_t *out_list);

/* Tags on `site` whose name starts with `prefix` (case-insensitive for ASCII),
 * ordered by how many cached posts carry them (most-used first) then name.
 * Feeds search-box autocomplete. Tags are already collected per-site as a
 * side effect of bunny_db_post_upsert(); this is a pure read. `prefix` may
 * contain any characters, including literal `%`/`_`/`\` -- they're matched
 * literally, not treated as SQL LIKE wildcards. */
bunny_db_result_t bunny_db_tag_autocomplete(bunny_db_t *db, bunny_db_site_t site, const char *prefix, int limit, bunny_db_tag_stat_list_t *out_list);

/* --- Action queue -------------------------------------------------------------
 * Proxies favorite/vote/comment calls to the sites (M4.3): an action is
 * enqueued here, then bunny_core_process_queue() (libs/core) drains it
 * against the real site API and marks it done/failed. bunny_db itself never
 * touches the network -- `payload` is an opaque blob (e.g. a vote's score) it
 * stores and returns as-is. */

bunny_db_result_t bunny_db_action_queue_add(bunny_db_t *db, int64_t post_id, bunny_db_action_type_t action_type, const char *payload, int64_t *out_id);
bunny_db_result_t bunny_db_action_queue_list_pending(bunny_db_t *db, bunny_db_action_list_t *out_list);
bunny_db_result_t bunny_db_action_queue_mark_done(bunny_db_t *db, int64_t action_id);
bunny_db_result_t bunny_db_action_queue_mark_failed(bunny_db_t *db, int64_t action_id, const char *error_message);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_DB_DB_H */
