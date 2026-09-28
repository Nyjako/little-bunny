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

/* --- Searches ------------------------------------------------------------ */

bunny_db_result_t bunny_db_search_create(bunny_db_t *db, bunny_db_site_t site, const char *label,
                                          const char *query, int interval_hours, int64_t *out_id);
bunny_db_result_t bunny_db_search_delete(bunny_db_t *db, int64_t search_id);
bunny_db_result_t bunny_db_search_list(bunny_db_t *db, bunny_db_search_list_t *out_list);
bunny_db_result_t bunny_db_search_touch_last_run(bunny_db_t *db, int64_t search_id);

/* --- Posts cache ----------------------------------------------------------
 * Upserts are keyed on (site, external_id): calling this again for a post
 * already cached updates it in place rather than duplicating it. */

typedef struct {
    bunny_db_site_t site;
    int64_t external_id;
    const char *artist;         /* may be NULL */
    const char *title;          /* may be NULL */
    const char *description;    /* may be NULL */
    const char *rating;         /* may be NULL */
    int score;
    int fav_count;
    int comment_count;
    const char *file_url;       /* may be NULL */
    const char *file_ext;       /* may be NULL */
    const char *file_md5;       /* may be NULL */
    const char *preview_url;    /* may be NULL */
    int width;
    int height;
    const char *created_at_site; /* may be NULL */
    const char **tags;          /* may be NULL */
    size_t tag_count;
} bunny_db_post_upsert_t;

bunny_db_result_t bunny_db_post_upsert(bunny_db_t *db, const bunny_db_post_upsert_t *post, int64_t *out_id);
bunny_db_result_t bunny_db_post_get(bunny_db_t *db, bunny_db_site_t site, int64_t external_id,
                                     bunny_db_post_t *out_post);

/* Associates a cached post with a search's result set (e.g. after running that
 * search against the site). Idempotent: re-adding the same pair is a no-op. */
bunny_db_result_t bunny_db_search_add_result(bunny_db_t *db, int64_t search_id, int64_t post_id);
bunny_db_result_t bunny_db_search_list_posts(bunny_db_t *db, int64_t search_id, bool unseen_only,
                                              bunny_db_post_list_t *out_list);

/* --- Seen state (global per post, not per search) ------------------------- */

bunny_db_result_t bunny_db_post_mark_seen(bunny_db_t *db, int64_t post_id);
bunny_db_result_t bunny_db_count_unseen(bunny_db_t *db, int64_t *out_count);

/* --- Favorites mirror ------------------------------------------------------
 * A local cache of what's favorited, so the app doesn't have to round-trip to
 * the site to show favorite state. Does not itself call any site API. */

bunny_db_result_t bunny_db_favorite_add(bunny_db_t *db, int64_t post_id, int stars /* -1 if not applicable */);
bunny_db_result_t bunny_db_favorite_remove(bunny_db_t *db, int64_t post_id);
bunny_db_result_t bunny_db_favorite_list(bunny_db_t *db, bunny_db_post_list_t *out_list);

/* --- Downloads -------------------------------------------------------------- */

bunny_db_result_t bunny_db_download_record(bunny_db_t *db, int64_t post_id, const char *file_path,
                                            const char *checksum_md5, bool verified, int64_t *out_id);
bunny_db_result_t bunny_db_download_list_for_post(bunny_db_t *db, int64_t post_id,
                                                   bunny_db_download_list_t *out_list);

/* --- Tag stats -------------------------------------------------------------- */

/* Tags of currently-favorited posts, ordered by how many favorited posts carry
 * them, descending. Feeds the "most liked/favorited tags" feature (M10). */
bunny_db_result_t bunny_db_top_favorited_tags(bunny_db_t *db, int limit, bunny_db_tag_stat_list_t *out_list);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_DB_DB_H */
