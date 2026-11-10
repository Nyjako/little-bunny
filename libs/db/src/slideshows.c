#include "bunny_db/db.h"

#include <goblin/dyn_array.h>

#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "internal.h"

GOBLIN_DYN_ARRAY_DECL(bunny_db_slideshow, bunny_db_slideshow_t)
GOBLIN_DYN_ARRAY_DECL(bunny_db_slideshow_search, bunny_db_slideshow_search_t)
GOBLIN_DYN_ARRAY_DECL(bunny_db_slideshow_post, bunny_db_slideshow_post_t)
GOBLIN_DYN_ARRAY_DECL(bunny_db_post, bunny_db_post_t)
GOBLIN_DYN_ARRAY_DECL(bunny_db_int64, int64_t)

static void bind_nullable_int(sqlite3_stmt *stmt, int col, bool has_value, int value)
{
    if (has_value) {
        sqlite3_bind_int(stmt, col, value);
    } else {
        sqlite3_bind_null(stmt, col);
    }
}

static void fill_slideshow_from_row(sqlite3_stmt *stmt, bunny_db_slideshow_t *out)
{
    out->id = sqlite3_column_int64(stmt, 0);
    out->label = bunny_db_column_text_dup(stmt, 1);
    out->has_default_posts_per_search = sqlite3_column_type(stmt, 2) != SQLITE_NULL;
    out->default_posts_per_search = out->has_default_posts_per_search ? sqlite3_column_int(stmt, 2) : 0;
    out->has_max_total_posts = sqlite3_column_type(stmt, 3) != SQLITE_NULL;
    out->max_total_posts = out->has_max_total_posts ? sqlite3_column_int(stmt, 3) : 0;
    out->created_at = bunny_db_column_text_dup(stmt, 4);
}

bunny_db_result_t bunny_db_slideshow_create(bunny_db_t *db, const char *label, bool has_default_posts_per_search, int default_posts_per_search, bool has_max_total_posts, int max_total_posts, int64_t *out_id)
{
    if (!db || !label || !out_id) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "INSERT INTO slideshows (label, default_posts_per_search, max_total_posts) VALUES (?, ?, ?);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, label, -1, SQLITE_TRANSIENT);
    bind_nullable_int(stmt, 2, has_default_posts_per_search, default_posts_per_search);
    bind_nullable_int(stmt, 3, has_max_total_posts, max_total_posts);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) {
        return bunny_db_sqlite_rc_to_result(rc);
    }
    *out_id = sqlite3_last_insert_rowid(db->handle);
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_slideshow_update(bunny_db_t *db, int64_t slideshow_id, const char *label, bool has_default_posts_per_search, int default_posts_per_search, bool has_max_total_posts, int max_total_posts)
{
    if (!db || !label) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "UPDATE slideshows SET label = ?, default_posts_per_search = ?, max_total_posts = ? WHERE id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, label, -1, SQLITE_TRANSIENT);
    bind_nullable_int(stmt, 2, has_default_posts_per_search, default_posts_per_search);
    bind_nullable_int(stmt, 3, has_max_total_posts, max_total_posts);
    sqlite3_bind_int64(stmt, 4, slideshow_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_slideshow_delete(bunny_db_t *db, int64_t slideshow_id)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "DELETE FROM slideshows WHERE id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, slideshow_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_slideshow_get(bunny_db_t *db, int64_t slideshow_id, bunny_db_slideshow_t *out_slideshow)
{
    if (!db || !out_slideshow) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_slideshow, 0, sizeof(*out_slideshow));
    const char *sql = "SELECT id, label, default_posts_per_search, max_total_posts, created_at FROM slideshows WHERE id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, slideshow_id);
    int rc = sqlite3_step(stmt);
    if (rc != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        return rc == SQLITE_DONE ? BUNNY_DB_ERR_NOT_FOUND : bunny_db_sqlite_rc_to_result(rc);
    }
    fill_slideshow_from_row(stmt, out_slideshow);
    sqlite3_finalize(stmt);
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_slideshow_list(bunny_db_t *db, bunny_db_slideshow_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));
    const char *sql = "SELECT id, label, default_posts_per_search, max_total_posts, created_at FROM slideshows ORDER BY created_at ASC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    bunny_db_slideshow_array arr;
    bunny_db_slideshow_array_init(&arr);
    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        bunny_db_slideshow_t item;
        memset(&item, 0, sizeof(item));
        fill_slideshow_from_row(stmt, &item);
        if (!bunny_db_slideshow_array_push(&arr, item)) {
            sqlite3_finalize(stmt);
            bunny_db_slideshow_free(&item);
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_slideshow_free(&arr.items[i]);
            }
            bunny_db_slideshow_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            bunny_db_slideshow_free(&arr.items[i]);
        }
        bunny_db_slideshow_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }
    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_slideshow_search_add(bunny_db_t *db, int64_t slideshow_id, int64_t search_id, bool has_override_count, int override_count)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "INSERT INTO slideshow_searches (slideshow_id, search_id, override_count) VALUES (?, ?, ?) "
                      "ON CONFLICT(slideshow_id, search_id) DO UPDATE SET override_count = excluded.override_count;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, slideshow_id);
    sqlite3_bind_int64(stmt, 2, search_id);
    bind_nullable_int(stmt, 3, has_override_count, override_count);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_slideshow_search_remove(bunny_db_t *db, int64_t slideshow_id, int64_t search_id)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    bunny_db_begin_transaction(db);

    const char *del_posts_sql = "DELETE FROM slideshow_posts WHERE slideshow_id = ? AND search_id = ?;";
    sqlite3_stmt *del_posts_stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, del_posts_sql, -1, &del_posts_stmt, NULL) != SQLITE_OK) {
        bunny_db_rollback_transaction(db);
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(del_posts_stmt, 1, slideshow_id);
    sqlite3_bind_int64(del_posts_stmt, 2, search_id);
    int rc = sqlite3_step(del_posts_stmt);
    sqlite3_finalize(del_posts_stmt);
    if (rc != SQLITE_DONE) {
        bunny_db_rollback_transaction(db);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    const char *del_link_sql = "DELETE FROM slideshow_searches WHERE slideshow_id = ? AND search_id = ?;";
    sqlite3_stmt *del_link_stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, del_link_sql, -1, &del_link_stmt, NULL) != SQLITE_OK) {
        bunny_db_rollback_transaction(db);
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(del_link_stmt, 1, slideshow_id);
    sqlite3_bind_int64(del_link_stmt, 2, search_id);
    rc = sqlite3_step(del_link_stmt);
    sqlite3_finalize(del_link_stmt);
    if (rc != SQLITE_DONE) {
        bunny_db_rollback_transaction(db);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    bunny_db_commit_transaction(db);
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_slideshow_search_list(bunny_db_t *db, int64_t slideshow_id, bunny_db_slideshow_search_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));
    const char *sql = "SELECT slideshow_id, search_id, override_count, added_at FROM slideshow_searches WHERE slideshow_id = ? ORDER BY added_at ASC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, slideshow_id);
    bunny_db_slideshow_search_array arr;
    bunny_db_slideshow_search_array_init(&arr);
    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        bunny_db_slideshow_search_t item;
        memset(&item, 0, sizeof(item));
        item.slideshow_id = sqlite3_column_int64(stmt, 0);
        item.search_id = sqlite3_column_int64(stmt, 1);
        item.has_override_count = sqlite3_column_type(stmt, 2) != SQLITE_NULL;
        item.override_count = item.has_override_count ? sqlite3_column_int(stmt, 2) : 0;
        item.added_at = bunny_db_column_text_dup(stmt, 3);
        if (!bunny_db_slideshow_search_array_push(&arr, item)) {
            sqlite3_finalize(stmt);
            bunny_db_slideshow_search_free(&item);
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_slideshow_search_free(&arr.items[i]);
            }
            bunny_db_slideshow_search_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            bunny_db_slideshow_search_free(&arr.items[i]);
        }
        bunny_db_slideshow_search_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }
    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_slideshow_posts_list(bunny_db_t *db, int64_t slideshow_id, int64_t search_id, bunny_db_slideshow_post_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));
    /* sp.search_id trails every BUNNY_DB_POST_SELECT_COLUMNS column rather
     * than leading them, so bunny_db_fill_post_from_row (which always reads
     * starting at column 0, no offset parameter) can be reused unmodified
     * -- read separately afterward via BUNNY_DB_POST_SELECT_COLUMNS_COUNT,
     * the one place outside internal.h that needs to know that count. */
    const char *sql_all = "SELECT " BUNNY_DB_POST_SELECT_COLUMNS ", sp.search_id " BUNNY_DB_POST_SELECT_FROM_JOIN "JOIN slideshow_posts sp ON sp.post_id = p.id WHERE sp.slideshow_id = ?;";
    const char *sql_one_search = "SELECT " BUNNY_DB_POST_SELECT_COLUMNS ", sp.search_id " BUNNY_DB_POST_SELECT_FROM_JOIN "JOIN slideshow_posts sp ON sp.post_id = p.id WHERE sp.slideshow_id = ? AND sp.search_id = ?;";
    const char *sql = search_id > 0 ? sql_one_search : sql_all;
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, slideshow_id);
    if (search_id > 0) {
        sqlite3_bind_int64(stmt, 2, search_id);
    }
    bunny_db_slideshow_post_array arr;
    bunny_db_slideshow_post_array_init(&arr);
    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        bunny_db_slideshow_post_t item;
        memset(&item, 0, sizeof(item));
        bunny_db_fill_post_from_row(stmt, &item.post);
        item.search_id = sqlite3_column_int64(stmt, BUNNY_DB_POST_SELECT_COLUMNS_COUNT);
        if (!bunny_db_slideshow_post_array_push(&arr, item)) {
            sqlite3_finalize(stmt);
            bunny_db_slideshow_post_free(&item);
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_slideshow_post_free(&arr.items[i]);
            }
            bunny_db_slideshow_post_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            bunny_db_slideshow_post_free(&arr.items[i]);
        }
        bunny_db_slideshow_post_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }
    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_slideshow_posts_set(bunny_db_t *db, int64_t slideshow_id, int64_t search_id, const int64_t *post_ids, size_t count)
{
    if (!db || (count > 0 && !post_ids)) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    bunny_db_begin_transaction(db);

    const char *del_sql = "DELETE FROM slideshow_posts WHERE slideshow_id = ? AND search_id = ?;";
    sqlite3_stmt *del_stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, del_sql, -1, &del_stmt, NULL) != SQLITE_OK) {
        bunny_db_rollback_transaction(db);
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(del_stmt, 1, slideshow_id);
    sqlite3_bind_int64(del_stmt, 2, search_id);
    int rc = sqlite3_step(del_stmt);
    sqlite3_finalize(del_stmt);
    if (rc != SQLITE_DONE) {
        bunny_db_rollback_transaction(db);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    const char *ins_sql = "INSERT INTO slideshow_posts (slideshow_id, search_id, post_id) VALUES (?, ?, ?);";
    for (size_t i = 0; i < count; i++) {
        sqlite3_stmt *ins_stmt = NULL;
        if (sqlite3_prepare_v2(db->handle, ins_sql, -1, &ins_stmt, NULL) != SQLITE_OK) {
            bunny_db_rollback_transaction(db);
            return BUNNY_DB_ERR_QUERY_FAILED;
        }
        sqlite3_bind_int64(ins_stmt, 1, slideshow_id);
        sqlite3_bind_int64(ins_stmt, 2, search_id);
        sqlite3_bind_int64(ins_stmt, 3, post_ids[i]);
        rc = sqlite3_step(ins_stmt);
        sqlite3_finalize(ins_stmt);
        if (rc != SQLITE_DONE) {
            bunny_db_rollback_transaction(db);
            return bunny_db_sqlite_rc_to_result(rc);
        }
    }

    bunny_db_commit_transaction(db);
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_slideshow_post_replace(bunny_db_t *db, int64_t slideshow_id, int64_t search_id, int64_t old_post_id, int64_t new_post_id)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "UPDATE slideshow_posts SET post_id = ? WHERE slideshow_id = ? AND search_id = ? AND post_id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, new_post_id);
    sqlite3_bind_int64(stmt, 2, slideshow_id);
    sqlite3_bind_int64(stmt, 3, search_id);
    sqlite3_bind_int64(stmt, 4, old_post_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) {
        return bunny_db_sqlite_rc_to_result(rc);
    }
    if (sqlite3_changes(db->handle) == 0) {
        return BUNNY_DB_ERR_NOT_FOUND;
    }
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_slideshow_all_post_ids(bunny_db_t *db, int64_t slideshow_id, bunny_db_int64_list_t *out_ids)
{
    if (!db || !out_ids) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_ids, 0, sizeof(*out_ids));
    const char *sql = "SELECT post_id FROM slideshow_posts WHERE slideshow_id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, slideshow_id);
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
    out_ids->items = arr.items;
    out_ids->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_pool_search_list_posts_random(bunny_db_t *db, int64_t search_id, int64_t pool_id, int count, bunny_db_post_list_t *out_list)
{
    if (!db || !out_list || count <= 0) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    bunny_db_post_array arr;
    bunny_db_post_array_init(&arr);

    for (int page = 1;; page++) {
        bunny_db_post_list_t page_list;
        bunny_db_result_t result = bunny_db_pool_search_list_posts(db, search_id, pool_id, false, page, &page_list);
        if (result != BUNNY_DB_OK) {
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_post_free(&arr.items[i]);
            }
            bunny_db_post_array_free(&arr);
            return result;
        }
        for (size_t i = 0; i < page_list.count; i++) {
            if (!bunny_db_post_array_push(&arr, page_list.items[i])) {
                bunny_db_post_free(&page_list.items[i]);
                for (size_t j = i + 1; j < page_list.count; j++) {
                    bunny_db_post_free(&page_list.items[j]);
                }
                free(page_list.items);
                for (size_t j = 0; j < arr.count; j++) {
                    bunny_db_post_free(&arr.items[j]);
                }
                bunny_db_post_array_free(&arr);
                return BUNNY_DB_ERR_UNKNOWN;
            }
        }
        bool last_page = page_list.count < BUNNY_DB_SEARCH_POSTS_PAGE_SIZE;
        free(page_list.items); /* items themselves now owned by arr -- only the array storage is freed */
        if (last_page) {
            break;
        }
    }

    /* Fisher-Yates, in place -- seeded once at process start is fine here,
     * same as every other place in this codebase that just needs "random
     * enough for a slideshow pick," not cryptographic randomness. */
    for (size_t i = arr.count; i > 1; i--) {
        size_t j = (size_t)rand() % i;
        bunny_db_post_t tmp = arr.items[i - 1];
        arr.items[i - 1] = arr.items[j];
        arr.items[j] = tmp;
    }

    size_t take = (size_t)count < arr.count ? (size_t)count : arr.count;
    for (size_t i = take; i < arr.count; i++) {
        bunny_db_post_free(&arr.items[i]);
    }
    arr.count = take;

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}
