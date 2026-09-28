#include "bunny_db/db.h"

#include <stdlib.h>
#include <string.h>

#include "internal.h"

bunny_db_result_t bunny_db_post_upsert(bunny_db_t *db, const bunny_db_post_upsert_t *post, int64_t *out_id) {
    if (!db || !post) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql =
        "INSERT INTO posts (site, external_id, artist, title, description, rating, score, fav_count, "
        "comment_count, file_url, file_ext, file_md5, preview_url, width, height, created_at_site) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
        "ON CONFLICT(site, external_id) DO UPDATE SET "
        "  artist = excluded.artist, title = excluded.title, description = excluded.description, "
        "  rating = excluded.rating, score = excluded.score, fav_count = excluded.fav_count, "
        "  comment_count = excluded.comment_count, file_url = excluded.file_url, file_ext = excluded.file_ext, "
        "  file_md5 = excluded.file_md5, preview_url = excluded.preview_url, width = excluded.width, "
        "  height = excluded.height, created_at_site = excluded.created_at_site, "
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
        }
    }

    if (out_id) {
        *out_id = post_id;
    }
    return BUNNY_DB_OK;
}

void bunny_db_fill_post_from_row(sqlite3_stmt *stmt, bunny_db_post_t *out) {
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
}

bunny_db_result_t bunny_db_post_get(bunny_db_t *db, bunny_db_site_t site, int64_t external_id,
                                     bunny_db_post_t *out_post) {
    if (!db || !out_post) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "SELECT " BUNNY_DB_POST_SELECT_COLUMNS BUNNY_DB_POST_SELECT_FROM_JOIN
                       "WHERE p.site = ? AND p.external_id = ?;";
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

bunny_db_result_t bunny_db_search_add_result(bunny_db_t *db, int64_t search_id, int64_t post_id) {
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "INSERT OR IGNORE INTO search_results (search_id, post_id) VALUES (?, ?);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, search_id);
    sqlite3_bind_int64(stmt, 2, post_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_search_list_posts(bunny_db_t *db, int64_t search_id, bool unseen_only,
                                              bunny_db_post_list_t *out_list) {
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql_seen = "SELECT " BUNNY_DB_POST_SELECT_COLUMNS BUNNY_DB_POST_SELECT_FROM_JOIN
                            "JOIN search_results sr ON sr.post_id = p.id "
                            "WHERE sr.search_id = ? "
                            "ORDER BY sr.found_at DESC;";
    const char *sql_unseen = "SELECT " BUNNY_DB_POST_SELECT_COLUMNS BUNNY_DB_POST_SELECT_FROM_JOIN
                              "JOIN search_results sr ON sr.post_id = p.id "
                              "WHERE sr.search_id = ? AND seen.post_id IS NULL "
                              "ORDER BY sr.found_at DESC;";

    const char *sql = unseen_only ? sql_unseen : sql_seen;
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, search_id);

    size_t capacity = 0;
    size_t count = 0;
    bunny_db_post_t *items = NULL;
    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        if (count == capacity) {
            capacity = capacity == 0 ? 16 : capacity * 2;
            bunny_db_post_t *new_items = realloc(items, capacity * sizeof(bunny_db_post_t));
            if (!new_items) {
                sqlite3_finalize(stmt);
                for (size_t i = 0; i < count; i++) {
                    bunny_db_post_free(&items[i]);
                }
                free(items);
                return BUNNY_DB_ERR_UNKNOWN;
            }
            items = new_items;
        }
        memset(&items[count], 0, sizeof(items[count]));
        bunny_db_fill_post_from_row(stmt, &items[count]);
        count++;
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < count; i++) {
            bunny_db_post_free(&items[i]);
        }
        free(items);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = items;
    out_list->count = count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_post_mark_seen(bunny_db_t *db, int64_t post_id) {
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

bunny_db_result_t bunny_db_count_unseen(bunny_db_t *db, int64_t *out_count) {
    if (!db || !out_count) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql =
        "SELECT COUNT(*) FROM posts p LEFT JOIN seen_posts s ON s.post_id = p.id WHERE s.post_id IS NULL;";
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
