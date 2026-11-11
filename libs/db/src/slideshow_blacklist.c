#include "bunny_db/db.h"

#include <goblin/dyn_array.h>

#include <stdlib.h>
#include <string.h>

#include "internal.h"

GOBLIN_DYN_ARRAY_DECL(bunny_db_slideshow_blacklist_string, char *)

/* Same classification as blacklist.c's own rule_is_simple -- duplicated
 * rather than shared across translation units since it's two lines and
 * blacklist.c already keeps its copy `static`/private. */
static bool rule_is_simple(const char *rule)
{
    if (!*rule) {
        return false;
    }
    for (const char *p = rule; *p; p++) {
        if (*p == ' ' || *p == '~' || *p == '-' || *p == '*' || *p == '(' || *p == ')') {
            return false;
        }
    }
    return true;
}

/* Parses every "complex" slideshow-scoped rule under `dialect`, skipping any
 * that fail to parse -- same tolerance as bunny_db_blacklist_fetch_complex_rules,
 * except the dialect is an explicit parameter here rather than derived from a
 * `site` column, since a slideshow has no single site of its own (it can mix
 * e621 and Inkbunny searches). Every rule is stored/validated once, under
 * e621's dialect (see bunny_core_slideshow_blacklist_add) -- a caller that
 * wants to match against Inkbunny-sourced posts passes
 * BUNNY_TAG_QUERY_DIALECT_INKBUNNY here, which simply fails to parse (and so
 * silently skips) any rule using OR/wildcard/group syntax Inkbunny's stricter
 * grammar doesn't support, rather than that rule ever matching an
 * Inkbunny post. */
bunny_db_result_t bunny_db_slideshow_blacklist_fetch_complex_rules(bunny_db_t *db, int64_t slideshow_id, bunny_tag_query_dialect_t dialect, bunny_db_tag_query_node_ptr_array *out_asts)
{
    bunny_db_tag_query_node_ptr_array_init(out_asts);

    bunny_db_string_list_t rules;
    bunny_db_result_t result = bunny_db_slideshow_blacklist_list(db, slideshow_id, &rules);
    if (result != BUNNY_DB_OK) {
        return result;
    }

    for (size_t i = 0; i < rules.count; i++) {
        if (rule_is_simple(rules.items[i])) {
            continue;
        }
        bunny_tag_query_node_t *ast = NULL;
        if (bunny_tag_query_parse(rules.items[i], dialect, &ast, NULL)) {
            if (!bunny_db_tag_query_node_ptr_array_push(out_asts, ast)) {
                bunny_tag_query_free(ast);
            }
        }
    }
    bunny_db_string_list_free(&rules);
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_slideshow_blacklist_list(bunny_db_t *db, int64_t slideshow_id, bunny_db_string_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT tag FROM slideshow_blacklist_tags WHERE slideshow_id = ? ORDER BY tag ASC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, slideshow_id);

    bunny_db_slideshow_blacklist_string_array arr;
    bunny_db_slideshow_blacklist_string_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        char *tag = bunny_db_column_text_dup(stmt, 0);
        if (!bunny_db_slideshow_blacklist_string_array_push(&arr, tag)) {
            sqlite3_finalize(stmt);
            free(tag);
            for (size_t i = 0; i < arr.count; i++) {
                free(arr.items[i]);
            }
            bunny_db_slideshow_blacklist_string_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            free(arr.items[i]);
        }
        bunny_db_slideshow_blacklist_string_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_slideshow_blacklist_add(bunny_db_t *db, int64_t slideshow_id, const char *tag)
{
    if (!db || !tag || !*tag) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "INSERT OR IGNORE INTO slideshow_blacklist_tags (slideshow_id, tag) VALUES (?, ?);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, slideshow_id);
    sqlite3_bind_text(stmt, 2, tag, -1, SQLITE_TRANSIENT);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_slideshow_blacklist_remove(bunny_db_t *db, int64_t slideshow_id, const char *tag)
{
    if (!db || !tag || !*tag) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "DELETE FROM slideshow_blacklist_tags WHERE slideshow_id = ? AND tag = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, slideshow_id);
    sqlite3_bind_text(stmt, 2, tag, -1, SQLITE_TRANSIENT);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}
