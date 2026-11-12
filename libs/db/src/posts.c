#include "bunny_db/db.h"

#include <goblin/dyn_array.h>

#include <stdlib.h>
#include <string.h>

#include "internal.h"

GOBLIN_DYN_ARRAY_DECL(bunny_db_post, bunny_db_post_t)
GOBLIN_DYN_ARRAY_DECL(bunny_db_post_tag, bunny_db_post_tag_t)
GOBLIN_DYN_ARRAY_DECL(bunny_db_string, char *)
GOBLIN_DYN_ARRAY_DECL(bunny_db_int64, int64_t)
GOBLIN_DYN_ARRAY_DECL(bunny_db_post_file, bunny_db_post_file_t)
GOBLIN_DYN_ARRAY_DECL(bunny_db_inkbunny_pool_ref, bunny_db_inkbunny_pool_ref_t)

/* Per-row rating/media-type bucket, bitwise-ANDed against a caller-supplied
 * mask (M28) -- see the BUNNY_DB_RATING_MASK_ and BUNNY_DB_MEDIA_MASK_
 * constants in db.h for the bit meanings. Mirrors app/lib/widgets/rating_badge.dart's own per-site
 * bucketing exactly (explicit `p.site =` guards, not just hoping e621's
 * single-char ratings and Inkbunny's free-text rating_name never collide) --
 * keep the two in sync if either changes. Always ends in an ELSE so this can
 * never evaluate to SQL NULL (NULL & mask is NULL, which WHERE treats as
 * excluding the row -- not what an unrecognized rating/extension should do).
 * Touches only WHERE-clause inputs (p.rating/p.file_ext), never anything the
 * ORDER BY or the sr.post_sort_key index depends on -- see this file's own
 * big comment on bunny_db_search_list_posts for why that distinction matters
 * for this query's performance. */
#define BUNNY_DB_RATING_MASK_CASE                                                                                                                          \
    "(CASE WHEN p.site = 'e621' AND p.rating = 's' THEN 1 "                                                                                                \
    "WHEN p.site = 'e621' AND p.rating = 'q' THEN 2 "                                                                                                      \
    "WHEN p.site = 'e621' AND p.rating = 'e' THEN 4 "                                                                                                      \
    "WHEN p.site = 'inkbunny' AND (LOWER(p.rating) LIKE '%general%' OR LOWER(p.rating) LIKE '%safe%') THEN 1 "                                             \
    "WHEN p.site = 'inkbunny' AND (LOWER(p.rating) LIKE '%mature%' OR LOWER(p.rating) LIKE '%moderate%' OR LOWER(p.rating) LIKE '%questionable%') THEN 2 " \
    "WHEN p.site = 'inkbunny' AND (LOWER(p.rating) LIKE '%explicit%' OR LOWER(p.rating) LIKE '%adult%') THEN 4 "                                           \
    "ELSE 8 END)"

/* webm/mp4 can't be reliably split into "video" vs. a silent gif-style loop
 * without downloading and probing the file (neither e621's nor Inkbunny's
 * API exposes a duration/has-audio field) -- both bucket as "video" here,
 * matching app/lib/util/media_type.dart's own isVideoExt/isGifExt exactly. A
 * NULL file_ext (e.g. a not-yet-refreshed post) falls into "image" via the
 * ELSE, same "don't hide things by default" reasoning as the rating case's
 * unknown bucket. */
#define BUNNY_DB_MEDIA_MASK_CASE "(CASE WHEN LOWER(p.file_ext) IN ('webm', 'mp4') THEN 2 WHEN LOWER(p.file_ext) = 'gif' THEN 4 ELSE 1 END)"

bunny_db_result_t bunny_db_post_upsert(bunny_db_t *db, const bunny_db_post_upsert_t *post, int64_t *out_id)
{
    if (!db || !post) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "INSERT INTO posts (site, external_id, artist, title, description, rating, score, fav_count, "
                      "comment_count, file_url, file_ext, file_md5, preview_url, width, height, created_at_site, "
                      "score_up, score_down) "
                      "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
                      "ON CONFLICT(site, external_id) DO UPDATE SET "
                      "  artist = excluded.artist, title = excluded.title, description = excluded.description, "
                      "  rating = excluded.rating, score = excluded.score, fav_count = excluded.fav_count, "
                      "  comment_count = excluded.comment_count, file_url = excluded.file_url, file_ext = excluded.file_ext, "
                      "  file_md5 = excluded.file_md5, preview_url = excluded.preview_url, width = excluded.width, "
                      "  height = excluded.height, created_at_site = excluded.created_at_site, "
                      "  score_up = excluded.score_up, score_down = excluded.score_down, "
                      "  cached_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') "
                      "RETURNING id;";

    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }

    sqlite3_bind_text(stmt, 1, bunny_db_site_to_string(post->site), -1, SQLITE_STATIC);
    sqlite3_bind_int64(stmt, 2, post->external_id);
    bunny_db_bind_text_or_null(stmt, 3, post->artist);
    bunny_db_bind_text_or_null(stmt, 4, post->title);
    bunny_db_bind_text_or_null(stmt, 5, post->description);
    bunny_db_bind_text_or_null(stmt, 6, post->rating);
    sqlite3_bind_int(stmt, 7, post->score);
    sqlite3_bind_int(stmt, 8, post->fav_count);
    sqlite3_bind_int(stmt, 9, post->comment_count);
    bunny_db_bind_text_or_null(stmt, 10, post->file_url);
    bunny_db_bind_text_or_null(stmt, 11, post->file_ext);
    bunny_db_bind_text_or_null(stmt, 12, post->file_md5);
    bunny_db_bind_text_or_null(stmt, 13, post->preview_url);
    sqlite3_bind_int(stmt, 14, post->width);
    sqlite3_bind_int(stmt, 15, post->height);
    bunny_db_bind_text_or_null(stmt, 16, post->created_at_site);
    sqlite3_bind_int(stmt, 17, post->score_up);
    sqlite3_bind_int(stmt, 18, post->score_down);

    int rc = sqlite3_step(stmt);
    int64_t post_id = 0;
    if (rc == SQLITE_ROW) {
        post_id = sqlite3_column_int64(stmt, 0);
        rc = sqlite3_step(stmt); /* drain to SQLITE_DONE */
    }
    sqlite3_finalize(stmt);

    if (post_id == 0) {
        return bunny_db_sqlite_rc_to_result(rc);
    }

    /* Replace this post's tags wholesale: a re-fetch may have added/removed
     * tags since the last time this post was cached. */
    const char *del_sql = "DELETE FROM post_tags WHERE post_id = ?;";
    sqlite3_stmt *del_stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, del_sql, -1, &del_stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(del_stmt, 1, post_id);
        sqlite3_step(del_stmt);
        sqlite3_finalize(del_stmt);
    }

    for (size_t i = 0; i < post->tag_count; i++) {
        const char *tag_name = post->tags[i];
        if (!tag_name || !tag_name[0]) {
            continue;
        }

        const char *tag_sql = "INSERT INTO tags (site, name) VALUES (?, ?) "
                              "ON CONFLICT(site, name) DO UPDATE SET name = excluded.name "
                              "RETURNING id;";
        sqlite3_stmt *tag_stmt = NULL;
        if (sqlite3_prepare_v2(db->handle, tag_sql, -1, &tag_stmt, NULL) != SQLITE_OK) {
            continue;
        }
        sqlite3_bind_text(tag_stmt, 1, bunny_db_site_to_string(post->site), -1, SQLITE_STATIC);
        sqlite3_bind_text(tag_stmt, 2, tag_name, -1, SQLITE_TRANSIENT);

        int64_t tag_id = 0;
        if (sqlite3_step(tag_stmt) == SQLITE_ROW) {
            tag_id = sqlite3_column_int64(tag_stmt, 0);
        }
        sqlite3_finalize(tag_stmt);

        if (tag_id != 0) {
            const char *link_sql = "INSERT OR IGNORE INTO post_tags (post_id, tag_id) VALUES (?, ?);";
            sqlite3_stmt *link_stmt = NULL;
            if (sqlite3_prepare_v2(db->handle, link_sql, -1, &link_stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_int64(link_stmt, 1, post_id);
                sqlite3_bind_int64(link_stmt, 2, tag_id);
                sqlite3_step(link_stmt);
                sqlite3_finalize(link_stmt);
            }

            /* A tag's category is a property of the tag itself (see
             * schema.h), not this post -- upsert it once per tag regardless
             * of how many posts reference it. */
            const char *category = post->tag_categories ? post->tag_categories[i] : NULL;
            if (category && category[0]) {
                const char *category_sql = "INSERT INTO tag_categories (tag_id, category) VALUES (?, ?) "
                                           "ON CONFLICT(tag_id) DO UPDATE SET category = excluded.category;";
                sqlite3_stmt *category_stmt = NULL;
                if (sqlite3_prepare_v2(db->handle, category_sql, -1, &category_stmt, NULL) == SQLITE_OK) {
                    sqlite3_bind_int64(category_stmt, 1, tag_id);
                    sqlite3_bind_text(category_stmt, 2, category, -1, SQLITE_TRANSIENT);
                    sqlite3_step(category_stmt);
                    sqlite3_finalize(category_stmt);
                }
            }
        }
    }

    /* Replace this post's sources wholesale, same reasoning as post_tags
     * above -- a re-fetch may have added/removed/reordered sources. */
    const char *del_sources_sql = "DELETE FROM post_sources WHERE post_id = ?;";
    sqlite3_stmt *del_sources_stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, del_sources_sql, -1, &del_sources_stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(del_sources_stmt, 1, post_id);
        sqlite3_step(del_sources_stmt);
        sqlite3_finalize(del_sources_stmt);
    }

    for (size_t i = 0; i < post->source_count; i++) {
        const char *url = post->sources[i];
        if (!url || !url[0]) {
            continue;
        }

        const char *source_sql = "INSERT INTO post_sources (post_id, position, url) VALUES (?, ?, ?);";
        sqlite3_stmt *source_stmt = NULL;
        if (sqlite3_prepare_v2(db->handle, source_sql, -1, &source_stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(source_stmt, 1, post_id);
            sqlite3_bind_int(source_stmt, 2, (int)i);
            sqlite3_bind_text(source_stmt, 3, url, -1, SQLITE_TRANSIENT);
            sqlite3_step(source_stmt);
            sqlite3_finalize(source_stmt);
        }
    }

    /* Replace this post's files wholesale, same reasoning as post_sources
     * above -- purely additive alongside the single-file columns already
     * bound earlier in this function (M28). */
    const char *del_files_sql = "DELETE FROM post_files WHERE post_id = ?;";
    sqlite3_stmt *del_files_stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, del_files_sql, -1, &del_files_stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(del_files_stmt, 1, post_id);
        sqlite3_step(del_files_stmt);
        sqlite3_finalize(del_files_stmt);
    }

    for (size_t i = 0; i < post->file_count; i++) {
        const bunny_db_post_file_upsert_t *file = &post->files[i];
        if (!file->file_url || !file->file_url[0]) {
            continue;
        }

        const char *file_sql = "INSERT INTO post_files (post_id, position, file_url, sample_url, preview_url, file_ext, file_md5, width, height, mimetype) "
                               "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";
        sqlite3_stmt *file_stmt = NULL;
        if (sqlite3_prepare_v2(db->handle, file_sql, -1, &file_stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(file_stmt, 1, post_id);
            sqlite3_bind_int(file_stmt, 2, (int)i);
            sqlite3_bind_text(file_stmt, 3, file->file_url, -1, SQLITE_TRANSIENT);
            bunny_db_bind_text_or_null(file_stmt, 4, file->sample_url);
            bunny_db_bind_text_or_null(file_stmt, 5, file->preview_url);
            bunny_db_bind_text_or_null(file_stmt, 6, file->file_ext);
            bunny_db_bind_text_or_null(file_stmt, 7, file->file_md5);
            sqlite3_bind_int(file_stmt, 8, file->width);
            sqlite3_bind_int(file_stmt, 9, file->height);
            bunny_db_bind_text_or_null(file_stmt, 10, file->mimetype);
            sqlite3_step(file_stmt);
            sqlite3_finalize(file_stmt);
        }
    }

    /* Always upsert the relationships row (even when both fields are
     * "empty") so a resync that drops a parent/active-children flag is
     * reflected, not stuck at a stale prior value. */
    const char *relationships_sql = "INSERT INTO post_relationships (post_id, parent_external_id, has_active_children) VALUES (?, ?, ?) "
                                    "ON CONFLICT(post_id) DO UPDATE SET parent_external_id = excluded.parent_external_id, "
                                    "has_active_children = excluded.has_active_children;";
    sqlite3_stmt *relationships_stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, relationships_sql, -1, &relationships_stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(relationships_stmt, 1, post_id);
        if (post->has_parent) {
            sqlite3_bind_int64(relationships_stmt, 2, post->parent_external_id);
        } else {
            sqlite3_bind_null(relationships_stmt, 2);
        }
        sqlite3_bind_int(relationships_stmt, 3, post->has_active_children ? 1 : 0);
        sqlite3_step(relationships_stmt);
        sqlite3_finalize(relationships_stmt);
    }

    /* Always upsert the media-variants row too, same one-to-one reasoning as
     * post_relationships above -- a resync that loses a sample/screen URL
     * (e.g. the site stopped providing one) should clear it, not leave a
     * stale value. */
    const char *media_sql = "INSERT INTO post_media_variants (post_id, sample_url) VALUES (?, ?) "
                            "ON CONFLICT(post_id) DO UPDATE SET sample_url = excluded.sample_url;";
    sqlite3_stmt *media_stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, media_sql, -1, &media_stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(media_stmt, 1, post_id);
        bunny_db_bind_text_or_null(media_stmt, 2, post->sample_url);
        sqlite3_step(media_stmt);
        sqlite3_finalize(media_stmt);
    }

    /* Replace this post's children/pools wholesale, same reasoning as
     * post_sources above. */
    const char *del_children_sql = "DELETE FROM post_children WHERE post_id = ?;";
    sqlite3_stmt *del_children_stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, del_children_sql, -1, &del_children_stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(del_children_stmt, 1, post_id);
        sqlite3_step(del_children_stmt);
        sqlite3_finalize(del_children_stmt);
    }
    for (size_t i = 0; i < post->child_count; i++) {
        const char *child_sql = "INSERT OR IGNORE INTO post_children (post_id, child_external_id) VALUES (?, ?);";
        sqlite3_stmt *child_stmt = NULL;
        if (sqlite3_prepare_v2(db->handle, child_sql, -1, &child_stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(child_stmt, 1, post_id);
            sqlite3_bind_int64(child_stmt, 2, post->child_external_ids[i]);
            sqlite3_step(child_stmt);
            sqlite3_finalize(child_stmt);
        }
    }

    /* Unlike post_children above, this can't just delete-then-reinsert
     * wholesale -- that would wipe out `position` (M26, the post's index in
     * e621's own post_ids order for that pool) on every single resync. Only
     * memberships this post no longer actually has get deleted; ones it
     * still has keep their existing row (and position) completely
     * untouched. New memberships seed position to -1 ("not yet determined")
     * -- the next pool-order sync fills it in. */
    if (post->pool_count > 0) {
        char del_pools_sql[512] = "DELETE FROM post_pools WHERE post_id = ? AND pool_id NOT IN (";
        size_t offset = strlen(del_pools_sql);
        for (size_t i = 0; i < post->pool_count && offset + 4 < sizeof(del_pools_sql); i++) {
            offset += (size_t)snprintf(del_pools_sql + offset, sizeof(del_pools_sql) - offset, i == 0 ? "?" : ",?");
        }
        snprintf(del_pools_sql + offset, sizeof(del_pools_sql) - offset, ");");

        sqlite3_stmt *del_pools_stmt = NULL;
        if (sqlite3_prepare_v2(db->handle, del_pools_sql, -1, &del_pools_stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(del_pools_stmt, 1, post_id);
            for (size_t i = 0; i < post->pool_count; i++) {
                sqlite3_bind_int64(del_pools_stmt, (int)(i + 2), post->pool_ids[i]);
            }
            sqlite3_step(del_pools_stmt);
            sqlite3_finalize(del_pools_stmt);
        }
    } else {
        const char *del_all_pools_sql = "DELETE FROM post_pools WHERE post_id = ?;";
        sqlite3_stmt *del_all_pools_stmt = NULL;
        if (sqlite3_prepare_v2(db->handle, del_all_pools_sql, -1, &del_all_pools_stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(del_all_pools_stmt, 1, post_id);
            sqlite3_step(del_all_pools_stmt);
            sqlite3_finalize(del_all_pools_stmt);
        }
    }
    for (size_t i = 0; i < post->pool_count; i++) {
        const char *pool_sql = "INSERT INTO post_pools (post_id, pool_id, position) VALUES (?, ?, -1) ON CONFLICT(post_id, pool_id) DO NOTHING;";
        sqlite3_stmt *pool_stmt = NULL;
        if (sqlite3_prepare_v2(db->handle, pool_sql, -1, &pool_stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(pool_stmt, 1, post_id);
            sqlite3_bind_int64(pool_stmt, 2, post->pool_ids[i]);
            sqlite3_step(pool_stmt);
            sqlite3_finalize(pool_stmt);
        }
    }

    if (out_id) {
        *out_id = post_id;
    }
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_post_get_relationships(bunny_db_t *db, int64_t post_id, bunny_db_post_relationships_t *out_relationships)
{
    if (!db || !out_relationships) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_relationships, 0, sizeof(*out_relationships));

    const char *sql = "SELECT parent_external_id, has_active_children FROM post_relationships WHERE post_id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);

    int rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        if (sqlite3_column_type(stmt, 0) != SQLITE_NULL) {
            out_relationships->has_parent = true;
            out_relationships->parent_external_id = sqlite3_column_int64(stmt, 0);
        }
        out_relationships->has_active_children = sqlite3_column_int(stmt, 1) != 0;
        rc = sqlite3_step(stmt); /* drain to SQLITE_DONE */
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE && rc != SQLITE_ROW) {
        return bunny_db_sqlite_rc_to_result(rc);
    }

    const char *children_sql = "SELECT child_external_id FROM post_children WHERE post_id = ? ORDER BY child_external_id ASC;";
    sqlite3_stmt *children_stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, children_sql, -1, &children_stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(children_stmt, 1, post_id);

    bunny_db_int64_array arr;
    bunny_db_int64_array_init(&arr);

    while ((rc = sqlite3_step(children_stmt)) == SQLITE_ROW) {
        if (!bunny_db_int64_array_push(&arr, sqlite3_column_int64(children_stmt, 0))) {
            sqlite3_finalize(children_stmt);
            bunny_db_int64_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(children_stmt);

    if (rc != SQLITE_DONE) {
        bunny_db_int64_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_relationships->children.items = arr.items;
    out_relationships->children.count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_post_get_pool_ids(bunny_db_t *db, int64_t post_id, bunny_db_int64_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT pool_id FROM post_pools WHERE post_id = ? ORDER BY pool_id ASC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);

    bunny_db_int64_array arr;
    bunny_db_int64_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        if (!bunny_db_int64_array_push(&arr, sqlite3_column_int64(stmt, 0))) {
            sqlite3_finalize(stmt);
            bunny_db_int64_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        bunny_db_int64_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_inkbunny_post_get_pools(bunny_db_t *db, int64_t post_id, bunny_db_inkbunny_pool_ref_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT pool_id, pool_name FROM inkbunny_post_pools WHERE post_id = ? ORDER BY pool_id ASC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);

    bunny_db_inkbunny_pool_ref_array arr;
    bunny_db_inkbunny_pool_ref_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        bunny_db_inkbunny_pool_ref_t item;
        item.pool_id = sqlite3_column_int64(stmt, 0);
        item.name = bunny_db_column_text_dup(stmt, 1);
        if (!bunny_db_inkbunny_pool_ref_array_push(&arr, item)) {
            sqlite3_finalize(stmt);
            bunny_db_inkbunny_pool_ref_free(&item);
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_inkbunny_pool_ref_free(&arr.items[i]);
            }
            bunny_db_inkbunny_pool_ref_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            bunny_db_inkbunny_pool_ref_free(&arr.items[i]);
        }
        bunny_db_inkbunny_pool_ref_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_inkbunny_post_pools_replace(bunny_db_t *db, int64_t post_id, const bunny_db_inkbunny_pool_ref_t *pools, size_t pool_count)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *del_sql = "DELETE FROM inkbunny_post_pools WHERE post_id = ?;";
    sqlite3_stmt *del_stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, del_sql, -1, &del_stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(del_stmt, 1, post_id);
    sqlite3_step(del_stmt);
    sqlite3_finalize(del_stmt);

    for (size_t i = 0; i < pool_count; i++) {
        const char *insert_sql = "INSERT INTO inkbunny_post_pools (post_id, pool_id, pool_name) VALUES (?, ?, ?);";
        sqlite3_stmt *insert_stmt = NULL;
        if (sqlite3_prepare_v2(db->handle, insert_sql, -1, &insert_stmt, NULL) != SQLITE_OK) {
            return BUNNY_DB_ERR_QUERY_FAILED;
        }
        sqlite3_bind_int64(insert_stmt, 1, post_id);
        sqlite3_bind_int64(insert_stmt, 2, pools[i].pool_id);
        bunny_db_bind_text_or_null(insert_stmt, 3, pools[i].name);
        sqlite3_step(insert_stmt);
        sqlite3_finalize(insert_stmt);
    }

    return BUNNY_DB_OK;
}

void bunny_db_fill_post_from_row(sqlite3_stmt *stmt, bunny_db_post_t *out)
{
    out->id = sqlite3_column_int64(stmt, 0);
    out->site = bunny_db_site_from_text((const char *)sqlite3_column_text(stmt, 1));
    out->external_id = sqlite3_column_int64(stmt, 2);
    out->artist = bunny_db_column_text_dup(stmt, 3);
    out->title = bunny_db_column_text_dup(stmt, 4);
    out->description = bunny_db_column_text_dup(stmt, 5);
    out->rating = bunny_db_column_text_dup(stmt, 6);
    out->score = sqlite3_column_int(stmt, 7);
    out->fav_count = sqlite3_column_int(stmt, 8);
    out->comment_count = sqlite3_column_int(stmt, 9);
    out->file_url = bunny_db_column_text_dup(stmt, 10);
    out->file_ext = bunny_db_column_text_dup(stmt, 11);
    out->file_md5 = bunny_db_column_text_dup(stmt, 12);
    out->preview_url = bunny_db_column_text_dup(stmt, 13);
    out->width = sqlite3_column_int(stmt, 14);
    out->height = sqlite3_column_int(stmt, 15);
    out->created_at_site = bunny_db_column_text_dup(stmt, 16);
    out->cached_at = bunny_db_column_text_dup(stmt, 17);
    out->is_seen = sqlite3_column_int(stmt, 18) != 0;
    out->is_favorited = sqlite3_column_int(stmt, 19) != 0;
    out->score_up = sqlite3_column_int(stmt, 20);
    out->score_down = sqlite3_column_int(stmt, 21);
    out->sample_url = bunny_db_column_text_dup(stmt, 22);
    out->user_vote = sqlite3_column_int(stmt, 23);
    out->favorite_stars = sqlite3_column_int(stmt, 24);
}

bunny_db_result_t bunny_db_post_get(bunny_db_t *db, bunny_db_site_t site, int64_t external_id, bunny_db_post_t *out_post)
{
    if (!db || !out_post) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "SELECT " BUNNY_DB_POST_SELECT_COLUMNS BUNNY_DB_POST_SELECT_FROM_JOIN "WHERE p.site = ? AND p.external_id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, bunny_db_site_to_string(site), -1, SQLITE_STATIC);
    sqlite3_bind_int64(stmt, 2, external_id);

    int rc = sqlite3_step(stmt);
    if (rc != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        return rc == SQLITE_DONE ? BUNNY_DB_ERR_NOT_FOUND : bunny_db_sqlite_rc_to_result(rc);
    }

    memset(out_post, 0, sizeof(*out_post));
    bunny_db_fill_post_from_row(stmt, out_post);
    sqlite3_finalize(stmt);
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_post_get_by_id(bunny_db_t *db, int64_t post_id, bunny_db_post_t *out_post)
{
    if (!db || !out_post) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "SELECT " BUNNY_DB_POST_SELECT_COLUMNS BUNNY_DB_POST_SELECT_FROM_JOIN "WHERE p.id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);

    int rc = sqlite3_step(stmt);
    if (rc != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        return rc == SQLITE_DONE ? BUNNY_DB_ERR_NOT_FOUND : bunny_db_sqlite_rc_to_result(rc);
    }

    memset(out_post, 0, sizeof(*out_post));
    bunny_db_fill_post_from_row(stmt, out_post);
    sqlite3_finalize(stmt);
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_search_add_result(bunny_db_t *db, int64_t search_id, int64_t post_id, bool *out_was_new)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    /* post_sort_key denormalizes bunny_db_search_list_posts' own sort expression
     * (COALESCE(created_at_site, cached_at)) onto this row so that query can use a
     * (search_id, post_sort_key) index for its ORDER BY instead of sorting every
     * matching row at read time (see migration 15's own comment). Frozen at
     * whichever value the post had the first time it was linked to this search --
     * never updated on a later resync, same as every other field on this row. In
     * practice this only matters for a post whose created_at_site is still NULL (no
     * known site creation date), since that's the only case where the COALESCE
     * fallback -- and therefore this value -- could otherwise have drifted on a
     * later resync. */
    const char *sql = "INSERT OR IGNORE INTO search_results (search_id, post_id, post_sort_key) "
                      "VALUES (?, ?, (SELECT COALESCE(p.created_at_site, p.cached_at) FROM posts p WHERE p.id = ?));";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, search_id);
    sqlite3_bind_int64(stmt, 2, post_id);
    sqlite3_bind_int64(stmt, 3, post_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (out_was_new) {
        *out_was_new = sqlite3_changes(db->handle) > 0;
    }
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_search_has_result(bunny_db_t *db, int64_t search_id, int64_t post_id, bool *out_has_result)
{
    if (!db || !out_has_result) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "SELECT 1 FROM search_results WHERE search_id = ? AND post_id = ? LIMIT 1;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, search_id);
    sqlite3_bind_int64(stmt, 2, post_id);
    int rc = sqlite3_step(stmt);
    *out_has_result = rc == SQLITE_ROW;
    sqlite3_finalize(stmt);
    return (rc == SQLITE_ROW || rc == SQLITE_DONE) ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_search_list_posts(bunny_db_t *db, int64_t search_id, bunny_db_site_t site, bool unseen_only, bool apply_blacklist, int rating_mask, int media_mask, int page, bunny_db_post_list_t *out_list)
{
    if (!db || !out_list || page < 1) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    /* Newest-post-first by the site's own creation date, not by when this
     * app happened to find it (sr.found_at) -- a single sync pass can link
     * posts spanning a wide date range all at once, so found_at doesn't
     * track actual recency. Sorts by sr.post_sort_key (migration 15), a
     * denormalized copy of COALESCE(p.created_at_site, p.cached_at) set once
     * when a post is first linked to a search (bunny_db_search_add_result) --
     * NOT by that same expression computed live against `posts` here, even
     * though the two are equivalent in value. Ordering by a plain column on
     * `search_results` itself lets the (search_id, post_sort_key) index
     * satisfy both this query's WHERE and its ORDER BY directly, so SQLite
     * can walk straight to the requested page; ordering by a COALESCE(...)
     * over two `posts` columns instead (the pre-M46 version of this query)
     * can't use any index for the ORDER BY at all, forcing a full sort of
     * every row matching this search_id before LIMIT/OFFSET could apply --
     * confirmed live at 12-14s for a single page of a 58k-post search.
     *
     * The NOT EXISTS clause (when apply_blacklist is true, M37) excludes any
     * post carrying a tag blacklisted for its own site (M13.3) -- skipped
     * for a favorites search (see bunny_core_is_favorites_query), which is
     * meant to show everything favorited, not a filtered subset. Matching
     * on t.site rather than joining the searches table means this clause
     * itself doesn't need `site` at all -- it's only taken as a parameter
     * for the SEPARATE complex-blacklist-rule pass below, over the page
     * this query already returned (M28/M54, see
     * bunny_db_post_is_blacklisted's own doc comment for what "complex"
     * means and why this is a second C-side pass rather than more SQL).
     *
     * The two mask clauses (M28) are always present in all four variants,
     * unlike unseen_only/apply_blacklist's own all-or-nothing branching --
     * BUNNY_DB_RATING_MASK_ALL/BUNNY_DB_MEDIA_MASK_ALL (passed when the
     * caller wants no filtering) make them pass every row for free rather
     * than needing yet more static SQL variants; see the macros' own doc
     * comments for why this can't regress the index usage this comment is
     * about. */
    const char *sql_seen_filtered = "SELECT " BUNNY_DB_POST_SELECT_COLUMNS BUNNY_DB_POST_SELECT_FROM_JOIN "JOIN search_results sr ON sr.post_id = p.id "
                                    "WHERE sr.search_id = ? "
                                    "AND NOT EXISTS (SELECT 1 FROM post_tags pt JOIN tags t ON t.id = pt.tag_id "
                                    "JOIN blacklist_tags bl ON bl.site = t.site AND bl.tag = t.name WHERE pt.post_id = p.id) "
                                    "AND " BUNNY_DB_RATING_MASK_CASE " & ? != 0 AND " BUNNY_DB_MEDIA_MASK_CASE " & ? != 0 "
                                    "ORDER BY sr.post_sort_key DESC LIMIT ? OFFSET ?;";
    const char *sql_seen_unfiltered = "SELECT " BUNNY_DB_POST_SELECT_COLUMNS BUNNY_DB_POST_SELECT_FROM_JOIN "JOIN search_results sr ON sr.post_id = p.id "
                                      "WHERE sr.search_id = ? "
                                      "AND " BUNNY_DB_RATING_MASK_CASE " & ? != 0 AND " BUNNY_DB_MEDIA_MASK_CASE " & ? != 0 "
                                      "ORDER BY sr.post_sort_key DESC LIMIT ? OFFSET ?;";
    const char *sql_unseen_filtered = "SELECT " BUNNY_DB_POST_SELECT_COLUMNS BUNNY_DB_POST_SELECT_FROM_JOIN "JOIN search_results sr ON sr.post_id = p.id "
                                      "WHERE sr.search_id = ? AND seen.post_id IS NULL "
                                      "AND NOT EXISTS (SELECT 1 FROM post_tags pt JOIN tags t ON t.id = pt.tag_id "
                                      "JOIN blacklist_tags bl ON bl.site = t.site AND bl.tag = t.name WHERE pt.post_id = p.id) "
                                      "AND " BUNNY_DB_RATING_MASK_CASE " & ? != 0 AND " BUNNY_DB_MEDIA_MASK_CASE " & ? != 0 "
                                      "ORDER BY sr.post_sort_key DESC LIMIT ? OFFSET ?;";
    const char *sql_unseen_unfiltered = "SELECT " BUNNY_DB_POST_SELECT_COLUMNS BUNNY_DB_POST_SELECT_FROM_JOIN "JOIN search_results sr ON sr.post_id = p.id "
                                        "WHERE sr.search_id = ? AND seen.post_id IS NULL "
                                        "AND " BUNNY_DB_RATING_MASK_CASE " & ? != 0 AND " BUNNY_DB_MEDIA_MASK_CASE " & ? != 0 "
                                        "ORDER BY sr.post_sort_key DESC LIMIT ? OFFSET ?;";

    const char *sql = unseen_only ? (apply_blacklist ? sql_unseen_filtered : sql_unseen_unfiltered) : (apply_blacklist ? sql_seen_filtered : sql_seen_unfiltered);
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, search_id);
    sqlite3_bind_int(stmt, 2, rating_mask);
    sqlite3_bind_int(stmt, 3, media_mask);
    sqlite3_bind_int(stmt, 4, BUNNY_DB_SEARCH_POSTS_PAGE_SIZE);
    sqlite3_bind_int64(stmt, 5, (int64_t)(page - 1) * BUNNY_DB_SEARCH_POSTS_PAGE_SIZE);

    bunny_db_post_array arr;
    bunny_db_post_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        bunny_db_post_t item;
        memset(&item, 0, sizeof(item));
        bunny_db_fill_post_from_row(stmt, &item);
        if (!bunny_db_post_array_push(&arr, item)) {
            sqlite3_finalize(stmt);
            bunny_db_post_free(&item);
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_post_free(&arr.items[i]);
            }
            bunny_db_post_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            bunny_db_post_free(&arr.items[i]);
        }
        bunny_db_post_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    /* Second pass (M28/M54): only runs when apply_blacklist is true AND
     * `site` has at least one complex rule -- a site with none (today, for
     * every existing user) costs nothing beyond the one indexed SELECT
     * bunny_db_blacklist_fetch_complex_rules itself runs. Re-fetches each
     * SURVIVING row's own tags (there's no way to push the full grammar
     * down into the SQL above without itself re-implementing the grammar)
     * and drops any that match, in place -- see this function's own doc
     * comment above for why a page can come back shorter than
     * BUNNY_DB_SEARCH_POSTS_PAGE_SIZE as a result. */
    if (apply_blacklist && arr.count > 0) {
        bunny_db_tag_query_node_ptr_array complex_asts;
        bunny_db_result_t complex_result = bunny_db_blacklist_fetch_complex_rules(db, site, &complex_asts);
        if (complex_result != BUNNY_DB_OK) {
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_post_free(&arr.items[i]);
            }
            bunny_db_post_array_free(&arr);
            return complex_result;
        }
        if (complex_asts.count > 0) {
            size_t write = 0;
            for (size_t read = 0; read < arr.count; read++) {
                bunny_db_string_list_t tag_names;
                bunny_db_post_get_tag_names(db, arr.items[read].id, &tag_names);
                bool blacklisted = false;
                for (size_t i = 0; i < complex_asts.count && !blacklisted; i++) {
                    blacklisted = bunny_tag_query_matches(complex_asts.items[i], (const char *const *)tag_names.items, tag_names.count);
                }
                bunny_db_string_list_free(&tag_names);
                if (blacklisted) {
                    bunny_db_post_free(&arr.items[read]);
                } else {
                    arr.items[write++] = arr.items[read];
                }
            }
            arr.count = write;
        }
        bunny_db_blacklist_free_rule_asts(&complex_asts);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

/* Appends "sr.search_id IN (?,?,...)" (count placeholders) to *sql at
 * *offset, growing *sql via realloc if needed -- helper for
 * bunny_db_search_list_posts_random's dynamic subquery building below,
 * where the number of selected searches isn't known at compile time
 * (unlike post_upsert's own small, bounded pool_ids IN-clause at the top of
 * this file). */
static bool bunny_db_append_in_clause(char **sql, size_t *cap, size_t *offset, size_t count)
{
    /* Each placeholder needs at most 2 bytes (",?"), plus a little slack
     * for the clause's own text. */
    size_t needed = *offset + count * 2 + 32;
    if (needed > *cap) {
        char *grown = realloc(*sql, needed);
        if (!grown) {
            return false;
        }
        *sql = grown;
        *cap = needed;
    }
    *offset += (size_t)snprintf(*sql + *offset, *cap - *offset, "%s", "sr.search_id IN (");
    for (size_t i = 0; i < count; i++) {
        *offset += (size_t)snprintf(*sql + *offset, *cap - *offset, "%s", i == 0 ? "?" : ",?");
    }
    *offset += (size_t)snprintf(*sql + *offset, *cap - *offset, "%s", ")");
    return true;
}

/* Builds one of the two (blacklist-on/off) subqueries for
 * bunny_db_search_list_posts_random below -- same column/join shape
 * bunny_db_search_list_posts above uses, minus pagination (this is a
 * one-shot random pick, not a paginated listing) plus a dynamic
 * sr.search_id IN (...) in place of a single "= ?". `slideshow_id` (0 means
 * "none") appends a SECOND, independent NOT EXISTS clause against
 * slideshow_blacklist_tags -- unlike `apply_blacklist`, this one is added to
 * BOTH subqueries whenever it's set, since the per-slideshow exclusion is
 * not favorites-exempt (see bunny_db_search_list_posts_random's own doc
 * comment). Its one bound parameter must be supplied by the caller right
 * after this subquery's own search_id IN-clause binds, before the
 * rating/media mask binds -- matching this clause's position in the SQL
 * text. Returns false on allocation failure. */
static bool bunny_db_build_random_subquery(char **sql, size_t *cap, size_t *offset, size_t id_count, bool apply_blacklist, int64_t slideshow_id)
{
    size_t needed = *offset + 1024;
    if (needed > *cap) {
        char *grown = realloc(*sql, needed);
        if (!grown) {
            return false;
        }
        *sql = grown;
        *cap = needed;
    }
    /* "%s", not the text as the format string directly -- BUNNY_DB_RATING_MASK_CASE
     * below contains literal '%' characters (SQL LIKE wildcards), which
     * snprintf would otherwise parse as its own format specifiers.
     *
     * SELECT DISTINCT, not a plain SELECT -- a post linked to more than one
     * of this subquery's own id_count search_ids joins search_results more
     * than once (one row per matching search_id), which plain UNION across
     * the *other* (filtered/unfiltered) subquery can't catch since that
     * only dedupes across the two subqueries, not within one. Safe here
     * since every BUNNY_DB_POST_SELECT_FROM_JOIN join is 1:1 or 0:1 per
     * post (seen/favorites/media variant/votes), so DISTINCT over the full
     * column set collapses back to exactly one row per real post. */
    *offset += (size_t)snprintf(*sql + *offset, *cap - *offset, "%s", "SELECT DISTINCT " BUNNY_DB_POST_SELECT_COLUMNS BUNNY_DB_POST_SELECT_FROM_JOIN "JOIN search_results sr ON sr.post_id = p.id WHERE ");
    if (!bunny_db_append_in_clause(sql, cap, offset, id_count)) {
        return false;
    }
    needed = *offset + 256;
    if (needed > *cap) {
        char *grown = realloc(*sql, needed);
        if (!grown) {
            return false;
        }
        *sql = grown;
        *cap = needed;
    }
    if (apply_blacklist) {
        *offset += (size_t)snprintf(*sql + *offset, *cap - *offset, "%s",
                                    " AND NOT EXISTS (SELECT 1 FROM post_tags pt JOIN tags t ON t.id = pt.tag_id "
                                    "JOIN blacklist_tags bl ON bl.site = t.site AND bl.tag = t.name WHERE pt.post_id = p.id)");
    }
    if (slideshow_id != 0) {
        needed = *offset + 256;
        if (needed > *cap) {
            char *grown = realloc(*sql, needed);
            if (!grown) {
                return false;
            }
            *sql = grown;
            *cap = needed;
        }
        *offset += (size_t)snprintf(*sql + *offset, *cap - *offset, "%s",
                                    " AND NOT EXISTS (SELECT 1 FROM post_tags pt JOIN tags t ON t.id = pt.tag_id "
                                    "JOIN slideshow_blacklist_tags sbl ON sbl.slideshow_id = ? AND sbl.tag = t.name WHERE pt.post_id = p.id)");
    }
    *offset += (size_t)snprintf(*sql + *offset, *cap - *offset, "%s", " AND " BUNNY_DB_RATING_MASK_CASE " & ? != 0 AND " BUNNY_DB_MEDIA_MASK_CASE " & ? != 0");
    return true;
}

bunny_db_result_t bunny_db_search_list_posts_random(bunny_db_t *db, const int64_t *search_ids, const bunny_db_site_t *sites, const bool *apply_blacklist_flags, size_t search_id_count, int64_t slideshow_id, int rating_mask, int media_mask, int count, bunny_db_post_list_t *out_list)
{
    if (!db || !out_list || !search_ids || !sites || !apply_blacklist_flags || search_id_count == 0 || count <= 0) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    /* Partition into "apply_blacklist" / "no blacklist" subsets (favorites
     * searches never apply blacklist, see bunny_core's own resolution --
     * every other search does) -- at most 2 subqueries, UNION'd below.
     * UNION (not UNION ALL) also dedupes a post pulled in by more than one
     * selected search for free, no C-side merge step needed. */
    int64_t *filtered_ids = malloc(search_id_count * sizeof(int64_t));
    int64_t *unfiltered_ids = malloc(search_id_count * sizeof(int64_t));
    if (!filtered_ids || !unfiltered_ids) {
        free(filtered_ids);
        free(unfiltered_ids);
        return BUNNY_DB_ERR_UNKNOWN;
    }
    size_t filtered_count = 0, unfiltered_count = 0;
    for (size_t i = 0; i < search_id_count; i++) {
        if (apply_blacklist_flags[i]) {
            filtered_ids[filtered_count++] = search_ids[i];
        } else {
            unfiltered_ids[unfiltered_count++] = search_ids[i];
        }
    }

    size_t cap = 2048;
    char *sql = malloc(cap);
    size_t offset = 0;
    bool build_ok = sql != NULL;
    if (build_ok) {
        sql[0] = '\0';
        offset += (size_t)snprintf(sql + offset, cap - offset, "%s", "SELECT * FROM (");
    }
    if (build_ok && filtered_count > 0) {
        build_ok = bunny_db_build_random_subquery(&sql, &cap, &offset, filtered_count, true, slideshow_id);
    }
    if (build_ok && filtered_count > 0 && unfiltered_count > 0) {
        size_t needed = offset + 16;
        if (needed > cap) {
            char *grown = realloc(sql, needed);
            build_ok = grown != NULL;
            if (build_ok) {
                sql = grown;
                cap = needed;
            }
        }
        if (build_ok) {
            offset += (size_t)snprintf(sql + offset, cap - offset, "%s", " UNION ");
        }
    }
    if (build_ok && unfiltered_count > 0) {
        build_ok = bunny_db_build_random_subquery(&sql, &cap, &offset, unfiltered_count, false, slideshow_id);
    }
    if (build_ok) {
        size_t needed = offset + 32;
        if (needed > cap) {
            char *grown = realloc(sql, needed);
            build_ok = grown != NULL;
            if (build_ok) {
                sql = grown;
                cap = needed;
            }
        }
    }
    if (build_ok) {
        offset += (size_t)snprintf(sql + offset, cap - offset, "%s", ") ORDER BY RANDOM() LIMIT ?;");
    }
    if (!build_ok) {
        free(filtered_ids);
        free(unfiltered_ids);
        free(sql);
        return BUNNY_DB_ERR_UNKNOWN;
    }

    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        free(filtered_ids);
        free(unfiltered_ids);
        free(sql);
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    free(sql);

    int bind_index = 1;
    if (filtered_count > 0) {
        for (size_t i = 0; i < filtered_count; i++) {
            sqlite3_bind_int64(stmt, bind_index++, filtered_ids[i]);
        }
        if (slideshow_id != 0) {
            sqlite3_bind_int64(stmt, bind_index++, slideshow_id);
        }
        sqlite3_bind_int(stmt, bind_index++, rating_mask);
        sqlite3_bind_int(stmt, bind_index++, media_mask);
    }
    if (unfiltered_count > 0) {
        for (size_t i = 0; i < unfiltered_count; i++) {
            sqlite3_bind_int64(stmt, bind_index++, unfiltered_ids[i]);
        }
        if (slideshow_id != 0) {
            sqlite3_bind_int64(stmt, bind_index++, slideshow_id);
        }
        sqlite3_bind_int(stmt, bind_index++, rating_mask);
        sqlite3_bind_int(stmt, bind_index++, media_mask);
    }
    sqlite3_bind_int(stmt, bind_index++, count);
    free(filtered_ids);
    free(unfiltered_ids);

    bunny_db_post_array arr;
    bunny_db_post_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        bunny_db_post_t item;
        memset(&item, 0, sizeof(item));
        bunny_db_fill_post_from_row(stmt, &item);
        if (!bunny_db_post_array_push(&arr, item)) {
            sqlite3_finalize(stmt);
            bunny_db_post_free(&item);
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_post_free(&arr.items[i]);
            }
            bunny_db_post_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            bunny_db_post_free(&arr.items[i]);
        }
        bunny_db_post_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    /* Complex-blacklist second pass (M28/M54), once per distinct site
     * actually present among the surviving rows -- unlike
     * bunny_db_search_list_posts (one search, one site),
     * bunny_db_blacklist_fetch_complex_rules only ever checks one site at a
     * time, and this result set can span both. Skipped entirely when
     * filtered_count is 0 (every selected search is a favorites search --
     * nothing here should be blacklist-filtered at all). When it does run,
     * it applies to every surviving row of a matching site, including one
     * that's *also* reachable via an unfiltered (favorites-type) search in
     * the same multi-select -- same accepted imprecision as the UNION
     * above already has no way to track "which subquery(ies) a
     * now-deduped row came from," and not worth the extra EXISTS-subquery
     * bookkeeping needed to special-case what is a narrow edge case
     * (selecting a favorites search alongside a regular one for the same
     * slideshow). */
    if (filtered_count > 0 && arr.count > 0) {
        for (int site_index = 0; site_index < 2; site_index++) {
            bunny_db_site_t site = (bunny_db_site_t)site_index;
            bool site_present = false;
            for (size_t i = 0; i < arr.count; i++) {
                if (arr.items[i].site == site) {
                    site_present = true;
                    break;
                }
            }
            if (!site_present) {
                continue;
            }
            bunny_db_tag_query_node_ptr_array complex_asts;
            bunny_db_result_t complex_result = bunny_db_blacklist_fetch_complex_rules(db, site, &complex_asts);
            if (complex_result != BUNNY_DB_OK) {
                for (size_t i = 0; i < arr.count; i++) {
                    bunny_db_post_free(&arr.items[i]);
                }
                bunny_db_post_array_free(&arr);
                return complex_result;
            }
            if (complex_asts.count > 0) {
                size_t write = 0;
                for (size_t read = 0; read < arr.count; read++) {
                    if (arr.items[read].site != site) {
                        arr.items[write++] = arr.items[read];
                        continue;
                    }
                    bunny_db_string_list_t tag_names;
                    bunny_db_post_get_tag_names(db, arr.items[read].id, &tag_names);
                    bool blacklisted = false;
                    for (size_t i = 0; i < complex_asts.count && !blacklisted; i++) {
                        blacklisted = bunny_tag_query_matches(complex_asts.items[i], (const char *const *)tag_names.items, tag_names.count);
                    }
                    bunny_db_string_list_free(&tag_names);
                    if (blacklisted) {
                        bunny_db_post_free(&arr.items[read]);
                    } else {
                        arr.items[write++] = arr.items[read];
                    }
                }
                arr.count = write;
            }
            bunny_db_blacklist_free_rule_asts(&complex_asts);
        }
    }

    /* Per-slideshow complex-blacklist second pass -- same per-distinct-site
     * shape as the per-site pass above, but gated on `slideshow_id != 0`
     * instead of `filtered_count > 0`: the per-slideshow exclusion is not
     * favorites-exempt, so it has to run even when every selected search is
     * a favorites search. Each site's rules are parsed under that SAME
     * site's own dialect (dialect_for_site below) even though every rule was
     * stored/validated once under e621's dialect at write time (see
     * bunny_core_slideshow_blacklist_add) -- a rule using OR/wildcard/group
     * syntax simply fails to parse under Inkbunny's stricter grammar and is
     * silently skipped for Inkbunny-sourced rows, rather than ever matching
     * them (same tolerance bunny_db_slideshow_blacklist_fetch_complex_rules
     * itself documents). */
    if (slideshow_id != 0 && arr.count > 0) {
        for (int site_index = 0; site_index < 2; site_index++) {
            bunny_db_site_t site = (bunny_db_site_t)site_index;
            bool site_present = false;
            for (size_t i = 0; i < arr.count; i++) {
                if (arr.items[i].site == site) {
                    site_present = true;
                    break;
                }
            }
            if (!site_present) {
                continue;
            }
            bunny_tag_query_dialect_t dialect = site == BUNNY_DB_SITE_INKBUNNY ? BUNNY_TAG_QUERY_DIALECT_INKBUNNY : BUNNY_TAG_QUERY_DIALECT_E621;
            bunny_db_tag_query_node_ptr_array complex_asts;
            bunny_db_result_t complex_result = bunny_db_slideshow_blacklist_fetch_complex_rules(db, slideshow_id, dialect, &complex_asts);
            if (complex_result != BUNNY_DB_OK) {
                for (size_t i = 0; i < arr.count; i++) {
                    bunny_db_post_free(&arr.items[i]);
                }
                bunny_db_post_array_free(&arr);
                return complex_result;
            }
            if (complex_asts.count > 0) {
                size_t write = 0;
                for (size_t read = 0; read < arr.count; read++) {
                    if (arr.items[read].site != site) {
                        arr.items[write++] = arr.items[read];
                        continue;
                    }
                    bunny_db_string_list_t tag_names;
                    bunny_db_post_get_tag_names(db, arr.items[read].id, &tag_names);
                    bool blacklisted = false;
                    for (size_t i = 0; i < complex_asts.count && !blacklisted; i++) {
                        blacklisted = bunny_tag_query_matches(complex_asts.items[i], (const char *const *)tag_names.items, tag_names.count);
                    }
                    bunny_db_string_list_free(&tag_names);
                    if (blacklisted) {
                        bunny_db_post_free(&arr.items[read]);
                    } else {
                        arr.items[write++] = arr.items[read];
                    }
                }
                arr.count = write;
            }
            bunny_db_blacklist_free_rule_asts(&complex_asts);
        }
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_pool_search_list_posts(bunny_db_t *db, int64_t search_id, int64_t pool_id, bool unseen_only, int page, bunny_db_post_list_t *out_list)
{
    if (!db || !out_list || page < 1) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    /* Never filters the blacklist (M37) -- a pool search is meant to show
     * every post actually in the pool, unlike bunny_db_search_list_posts.
     * Ordered by this pool's own position (M26) -- e621's real post_ids
     * order, ascending -- instead of newest-first by creation date. A post
     * whose position isn't known yet (-1, not yet covered by a pool-order
     * sync) sorts after every known one, itself ordered oldest-first by
     * creation date as a reasonable placeholder until it's filled in. */
    const char *sql_seen = "SELECT " BUNNY_DB_POST_SELECT_COLUMNS BUNNY_DB_POST_SELECT_FROM_JOIN "JOIN search_results sr ON sr.post_id = p.id "
                           "LEFT JOIN post_pools pp ON pp.post_id = p.id AND pp.pool_id = ? "
                           "WHERE sr.search_id = ? "
                           "ORDER BY (COALESCE(pp.position, -1) >= 0) DESC, pp.position ASC, COALESCE(p.created_at_site, p.cached_at) ASC LIMIT ? OFFSET ?;";
    const char *sql_unseen = "SELECT " BUNNY_DB_POST_SELECT_COLUMNS BUNNY_DB_POST_SELECT_FROM_JOIN "JOIN search_results sr ON sr.post_id = p.id "
                             "LEFT JOIN post_pools pp ON pp.post_id = p.id AND pp.pool_id = ? "
                             "WHERE sr.search_id = ? AND seen.post_id IS NULL "
                             "ORDER BY (COALESCE(pp.position, -1) >= 0) DESC, pp.position ASC, COALESCE(p.created_at_site, p.cached_at) ASC LIMIT ? OFFSET ?;";

    const char *sql = unseen_only ? sql_unseen : sql_seen;
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, pool_id);
    sqlite3_bind_int64(stmt, 2, search_id);
    sqlite3_bind_int(stmt, 3, BUNNY_DB_SEARCH_POSTS_PAGE_SIZE);
    sqlite3_bind_int64(stmt, 4, (int64_t)(page - 1) * BUNNY_DB_SEARCH_POSTS_PAGE_SIZE);

    bunny_db_post_array arr;
    bunny_db_post_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        bunny_db_post_t item;
        memset(&item, 0, sizeof(item));
        bunny_db_fill_post_from_row(stmt, &item);
        if (!bunny_db_post_array_push(&arr, item)) {
            sqlite3_finalize(stmt);
            bunny_db_post_free(&item);
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_post_free(&arr.items[i]);
            }
            bunny_db_post_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            bunny_db_post_free(&arr.items[i]);
        }
        bunny_db_post_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_pool_set_post_positions(bunny_db_t *db, int64_t pool_id, const int64_t *post_ids, size_t count)
{
    if (!db || (!post_ids && count > 0)) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    /* post_ids holds e621's EXTERNAL post ids (straight from GET
     * /pools/{id}.json); post_pools.post_id is the LOCAL id, so each
     * update resolves one from the other via posts(site, external_id) --
     * a no-op (0 rows affected) for any post not cached locally yet, or
     * not actually a member of this pool, both harmless (see this
     * function's doc comment in db.h). */
    const char *sql = "UPDATE post_pools SET position = ? "
                      "WHERE pool_id = ? AND post_id = (SELECT id FROM posts WHERE site = 'e621' AND external_id = ?);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }

    bunny_db_begin_transaction(db);
    for (size_t i = 0; i < count; i++) {
        sqlite3_bind_int(stmt, 1, (int)i);
        sqlite3_bind_int64(stmt, 2, pool_id);
        sqlite3_bind_int64(stmt, 3, post_ids[i]);
        sqlite3_step(stmt);
        sqlite3_reset(stmt);
    }
    sqlite3_finalize(stmt);
    bunny_db_commit_transaction(db);
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_list_distinct_pool_ids(bunny_db_t *db, bunny_db_int64_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT DISTINCT pool_id FROM post_pools ORDER BY pool_id ASC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }

    bunny_db_int64_array arr;
    bunny_db_int64_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        if (!bunny_db_int64_array_push(&arr, sqlite3_column_int64(stmt, 0))) {
            sqlite3_finalize(stmt);
            bunny_db_int64_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        bunny_db_int64_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_post_get_tags_by_category(bunny_db_t *db, int64_t post_id, bunny_db_post_tag_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT t.name, tc.category "
                      "FROM post_tags pt "
                      "JOIN tags t ON t.id = pt.tag_id "
                      "LEFT JOIN tag_categories tc ON tc.tag_id = t.id "
                      "WHERE pt.post_id = ? "
                      "ORDER BY t.name ASC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);

    bunny_db_post_tag_array arr;
    bunny_db_post_tag_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        bunny_db_post_tag_t item;
        item.name = bunny_db_column_text_dup(stmt, 0);
        item.category = bunny_db_column_text_dup(stmt, 1);
        if (!bunny_db_post_tag_array_push(&arr, item)) {
            sqlite3_finalize(stmt);
            bunny_db_post_tag_free(&item);
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_post_tag_free(&arr.items[i]);
            }
            bunny_db_post_tag_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            bunny_db_post_tag_free(&arr.items[i]);
        }
        bunny_db_post_tag_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_post_get_tag_names(bunny_db_t *db, int64_t post_id, bunny_db_string_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT t.name FROM post_tags pt JOIN tags t ON t.id = pt.tag_id WHERE pt.post_id = ? ORDER BY t.name ASC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);

    bunny_db_string_array arr;
    bunny_db_string_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        char *name = bunny_db_column_text_dup(stmt, 0);
        if (!bunny_db_string_array_push(&arr, name)) {
            sqlite3_finalize(stmt);
            free(name);
            for (size_t i = 0; i < arr.count; i++) {
                free(arr.items[i]);
            }
            bunny_db_string_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            free(arr.items[i]);
        }
        bunny_db_string_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_post_get_sources(bunny_db_t *db, int64_t post_id, bunny_db_string_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT url FROM post_sources WHERE post_id = ? ORDER BY position ASC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);

    bunny_db_string_array arr;
    bunny_db_string_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        char *url = bunny_db_column_text_dup(stmt, 0);
        if (!bunny_db_string_array_push(&arr, url)) {
            sqlite3_finalize(stmt);
            free(url);
            for (size_t i = 0; i < arr.count; i++) {
                free(arr.items[i]);
            }
            bunny_db_string_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            free(arr.items[i]);
        }
        bunny_db_string_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_post_get_files(bunny_db_t *db, int64_t post_id, bunny_db_post_file_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT file_url, sample_url, preview_url, file_ext, file_md5, width, height, mimetype "
                      "FROM post_files WHERE post_id = ? ORDER BY position ASC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);

    bunny_db_post_file_array arr;
    bunny_db_post_file_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        bunny_db_post_file_t item;
        item.file_url = bunny_db_column_text_dup(stmt, 0);
        item.sample_url = bunny_db_column_text_dup(stmt, 1);
        item.preview_url = bunny_db_column_text_dup(stmt, 2);
        item.file_ext = bunny_db_column_text_dup(stmt, 3);
        item.file_md5 = bunny_db_column_text_dup(stmt, 4);
        item.width = sqlite3_column_int(stmt, 5);
        item.height = sqlite3_column_int(stmt, 6);
        item.mimetype = bunny_db_column_text_dup(stmt, 7);
        if (!bunny_db_post_file_array_push(&arr, item)) {
            sqlite3_finalize(stmt);
            bunny_db_post_file_free(&item);
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_post_file_free(&arr.items[i]);
            }
            bunny_db_post_file_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            bunny_db_post_file_free(&arr.items[i]);
        }
        bunny_db_post_file_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_post_mark_seen(bunny_db_t *db, int64_t post_id)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "INSERT OR IGNORE INTO seen_posts (post_id) VALUES (?);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_search_mark_all_seen(bunny_db_t *db, int64_t search_id)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "INSERT OR IGNORE INTO seen_posts (post_id) SELECT post_id FROM search_results WHERE search_id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, search_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_count_unseen(bunny_db_t *db, int64_t *out_count)
{
    if (!db || !out_count) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "SELECT COUNT(*) FROM posts p LEFT JOIN seen_posts s ON s.post_id = p.id WHERE s.post_id IS NULL;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    int rc = sqlite3_step(stmt);
    if (rc != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        return bunny_db_sqlite_rc_to_result(rc);
    }
    *out_count = sqlite3_column_int64(stmt, 0);
    sqlite3_finalize(stmt);
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_post_mark_inkbunny_details_backfilled(bunny_db_t *db, int64_t post_id)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "UPDATE posts SET inkbunny_details_backfilled = 1 WHERE id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_inkbunny_list_thin_post_ids(bunny_db_t *db, int limit, bunny_db_int64_list_t *out_external_ids)
{
    if (!db || !out_external_ids || limit <= 0) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_external_ids, 0, sizeof(*out_external_ids));

    const char *sql = "SELECT external_id FROM posts WHERE site = 'inkbunny' AND inkbunny_details_backfilled = 0 LIMIT ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int(stmt, 1, limit);

    bunny_db_int64_array arr;
    bunny_db_int64_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        if (!bunny_db_int64_array_push(&arr, sqlite3_column_int64(stmt, 0))) {
            sqlite3_finalize(stmt);
            bunny_db_int64_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        bunny_db_int64_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_external_ids->items = arr.items;
    out_external_ids->count = arr.count;
    return BUNNY_DB_OK;
}
