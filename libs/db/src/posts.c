#include "bunny_db/db.h"

#include <goblin/dyn_array.h>

#include <stdlib.h>
#include <string.h>

#include "internal.h"

GOBLIN_DYN_ARRAY_DECL(bunny_db_post, bunny_db_post_t)
GOBLIN_DYN_ARRAY_DECL(bunny_db_post_tag, bunny_db_post_tag_t)
GOBLIN_DYN_ARRAY_DECL(bunny_db_string, char *)
GOBLIN_DYN_ARRAY_DECL(bunny_db_int64, int64_t)

/* Posts per page for bunny_db_search_list_posts/bunny_db_pool_search_list_posts
 * (see their own doc comments in db.h) -- a local DB listing, not a site API
 * page size, so this is chosen purely for a reasonable response size rather
 * than matching e621/Inkbunny's own limits. */
#define BUNNY_DB_SEARCH_POSTS_PAGE_SIZE 200

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

bunny_db_result_t bunny_db_search_list_posts(bunny_db_t *db, int64_t search_id, bool unseen_only, bool apply_blacklist, int page, bunny_db_post_list_t *out_list)
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
     * on t.site rather than joining the searches table means this works
     * without knowing this search's own site. */
    const char *sql_seen_filtered = "SELECT " BUNNY_DB_POST_SELECT_COLUMNS BUNNY_DB_POST_SELECT_FROM_JOIN "JOIN search_results sr ON sr.post_id = p.id "
                                    "WHERE sr.search_id = ? "
                                    "AND NOT EXISTS (SELECT 1 FROM post_tags pt JOIN tags t ON t.id = pt.tag_id "
                                    "JOIN blacklist_tags bl ON bl.site = t.site AND bl.tag = t.name WHERE pt.post_id = p.id) "
                                    "ORDER BY sr.post_sort_key DESC LIMIT ? OFFSET ?;";
    const char *sql_seen_unfiltered = "SELECT " BUNNY_DB_POST_SELECT_COLUMNS BUNNY_DB_POST_SELECT_FROM_JOIN "JOIN search_results sr ON sr.post_id = p.id "
                                      "WHERE sr.search_id = ? "
                                      "ORDER BY sr.post_sort_key DESC LIMIT ? OFFSET ?;";
    const char *sql_unseen_filtered = "SELECT " BUNNY_DB_POST_SELECT_COLUMNS BUNNY_DB_POST_SELECT_FROM_JOIN "JOIN search_results sr ON sr.post_id = p.id "
                                      "WHERE sr.search_id = ? AND seen.post_id IS NULL "
                                      "AND NOT EXISTS (SELECT 1 FROM post_tags pt JOIN tags t ON t.id = pt.tag_id "
                                      "JOIN blacklist_tags bl ON bl.site = t.site AND bl.tag = t.name WHERE pt.post_id = p.id) "
                                      "ORDER BY sr.post_sort_key DESC LIMIT ? OFFSET ?;";
    const char *sql_unseen_unfiltered = "SELECT " BUNNY_DB_POST_SELECT_COLUMNS BUNNY_DB_POST_SELECT_FROM_JOIN "JOIN search_results sr ON sr.post_id = p.id "
                                        "WHERE sr.search_id = ? AND seen.post_id IS NULL "
                                        "ORDER BY sr.post_sort_key DESC LIMIT ? OFFSET ?;";

    const char *sql = unseen_only ? (apply_blacklist ? sql_unseen_filtered : sql_unseen_unfiltered) : (apply_blacklist ? sql_seen_filtered : sql_seen_unfiltered);
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, search_id);
    sqlite3_bind_int(stmt, 2, BUNNY_DB_SEARCH_POSTS_PAGE_SIZE);
    sqlite3_bind_int64(stmt, 3, (int64_t)(page - 1) * BUNNY_DB_SEARCH_POSTS_PAGE_SIZE);

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
