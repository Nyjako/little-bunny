#ifndef BUNNY_DB_INTERNAL_H
#define BUNNY_DB_INTERNAL_H

#include <goblin/cstr.h>
#include <sqlite3.h>

#include <stdlib.h>
#include <string.h>

#include "bunny_db/db.h"

struct bunny_db
{
    sqlite3 *handle;
};

static inline bunny_db_result_t bunny_db_sqlite_rc_to_result(int rc)
{
    switch (rc) {
        case SQLITE_OK:
        case SQLITE_DONE:
        case SQLITE_ROW:
            return BUNNY_DB_OK;
        case SQLITE_CONSTRAINT:
            return BUNNY_DB_ERR_CONSTRAINT;
        default:
            return BUNNY_DB_ERR_QUERY_FAILED;
    }
}

static inline char *bunny_db_dup_or_null(const char *s)
{
    return s ? goblin_copy_cstr(s) : NULL;
}

/* Duplicates the TEXT column at `col` (or NULL if the column is SQL NULL). */
static inline char *bunny_db_column_text_dup(sqlite3_stmt *stmt, int col)
{
    const unsigned char *text = sqlite3_column_text(stmt, col);
    return text ? goblin_copy_cstr((const char *)text) : NULL;
}

static inline bunny_db_site_t bunny_db_site_from_text(const char *text)
{
    if (text && strcmp(text, "inkbunny") == 0) {
        return BUNNY_DB_SITE_INKBUNNY;
    }
    return BUNNY_DB_SITE_E621;
}

static inline void bunny_db_bind_text_or_null(sqlite3_stmt *stmt, int idx, const char *value)
{
    if (value) {
        sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, idx);
    }
}

/* Shared SELECT fragment for anything that returns a full bunny_db_post_t
 * (post_get, search_list_posts, favorite_list) so they stay in the same
 * column order that bunny_db_fill_post_from_row() expects. */
#define BUNNY_DB_POST_SELECT_COLUMNS                                                                  \
    "p.id, p.site, p.external_id, p.artist, p.title, p.description, p.rating, p.score, p.fav_count, " \
    "p.comment_count, p.file_url, p.file_ext, p.file_md5, p.preview_url, p.width, p.height, "         \
    "p.created_at_site, p.cached_at, (seen.post_id IS NOT NULL) AS is_seen, "                         \
    "(fav.post_id IS NOT NULL) AS is_favorited "

#define BUNNY_DB_POST_SELECT_FROM_JOIN                  \
    "FROM posts p "                                     \
    "LEFT JOIN seen_posts seen ON seen.post_id = p.id " \
    "LEFT JOIN favorites fav ON fav.post_id = p.id "

/* Defined in posts.c; expects a row shaped like BUNNY_DB_POST_SELECT_COLUMNS. */
void bunny_db_fill_post_from_row(sqlite3_stmt *stmt, bunny_db_post_t *out);

#endif /* BUNNY_DB_INTERNAL_H */
