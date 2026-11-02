#include "bunny_db/db.h"

#include <goblin/dyn_array.h>

#include <stdlib.h>
#include <string.h>

#include "internal.h"

GOBLIN_DYN_ARRAY_DECL(bunny_db_blacklist_string, char *)

static bunny_tag_query_dialect_t dialect_for_site(bunny_db_site_t site)
{
    return site == BUNNY_DB_SITE_INKBUNNY ? BUNNY_TAG_QUERY_DIALECT_INKBUNNY : BUNNY_TAG_QUERY_DIALECT_E621;
}

/* A rule is "simple" iff it's exactly one bare tag with no operators --
 * anything else (AND via a space, ~OR, -NOT, *wildcard, (group)) needs the
 * full grammar matcher. Deliberately conservative: a bare `-tag`/`~tag`
 * (negated/OR'd as a WHOLE standalone rule) is still classified complex
 * despite being "one atom," since it isn't semantically an exact-match
 * row -- `-young` as a standalone rule means "blacklist every post NOT
 * tagged young," nothing like what the fast exact-match join computes. */
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

void bunny_db_blacklist_free_rule_asts(bunny_db_tag_query_node_ptr_array *asts)
{
    for (size_t i = 0; i < asts->count; i++) {
        bunny_tag_query_free(asts->items[i]);
    }
    bunny_db_tag_query_node_ptr_array_free(asts);
}

/* Parses every "complex" (non-simple) blacklist rule for `site`, skipping
 * any that fail to parse under that site's dialect -- a rule stored via
 * bunny_core_blacklist_add was already validated at write time, so a
 * parse failure here would mean something else wrote it (or the dialect's
 * rules changed); either way, silently skipping it rather than failing
 * the whole blacklist check is the safer failure mode. Re-parses on every
 * call rather than caching ASTs across calls -- acceptable at the expected
 * scale of a few dozen manually-curated rules; see this project's own
 * M28/M54 planning notes if a future report of slowness traces here. */
bunny_db_result_t bunny_db_blacklist_fetch_complex_rules(bunny_db_t *db, bunny_db_site_t site, bunny_db_tag_query_node_ptr_array *out_asts)
{
    bunny_db_tag_query_node_ptr_array_init(out_asts);

    bunny_db_string_list_t rules;
    bunny_db_result_t result = bunny_db_blacklist_list(db, site, &rules);
    if (result != BUNNY_DB_OK) {
        return result;
    }

    bunny_tag_query_dialect_t dialect = dialect_for_site(site);
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

bunny_db_result_t bunny_db_blacklist_list(bunny_db_t *db, bunny_db_site_t site, bunny_db_string_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT tag FROM blacklist_tags WHERE site = ? ORDER BY tag ASC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, bunny_db_site_to_string(site), -1, SQLITE_STATIC);

    bunny_db_blacklist_string_array arr;
    bunny_db_blacklist_string_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        char *tag = bunny_db_column_text_dup(stmt, 0);
        if (!bunny_db_blacklist_string_array_push(&arr, tag)) {
            sqlite3_finalize(stmt);
            free(tag);
            for (size_t i = 0; i < arr.count; i++) {
                free(arr.items[i]);
            }
            bunny_db_blacklist_string_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            free(arr.items[i]);
        }
        bunny_db_blacklist_string_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_blacklist_add(bunny_db_t *db, bunny_db_site_t site, const char *tag)
{
    if (!db || !tag || !*tag) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "INSERT OR IGNORE INTO blacklist_tags (site, tag) VALUES (?, ?);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, bunny_db_site_to_string(site), -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, tag, -1, SQLITE_TRANSIENT);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_blacklist_remove(bunny_db_t *db, bunny_db_site_t site, const char *tag)
{
    if (!db || !tag || !*tag) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "DELETE FROM blacklist_tags WHERE site = ? AND tag = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, bunny_db_site_to_string(site), -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, tag, -1, SQLITE_TRANSIENT);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_post_is_blacklisted(bunny_db_t *db, bunny_db_site_t site, int64_t post_id, bool *out_is_blacklisted)
{
    if (!db || !out_is_blacklisted) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    /* Fast path, unchanged: a simple exact-match rule hit. */
    const char *sql = "SELECT 1 FROM post_tags pt JOIN tags t ON t.id = pt.tag_id "
                      "JOIN blacklist_tags bl ON bl.site = t.site AND bl.tag = t.name "
                      "WHERE pt.post_id = ? LIMIT 1;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);
    int rc = sqlite3_step(stmt);
    *out_is_blacklisted = rc == SQLITE_ROW;
    sqlite3_finalize(stmt);
    if (rc != SQLITE_ROW && rc != SQLITE_DONE) {
        return bunny_db_sqlite_rc_to_result(rc);
    }
    if (*out_is_blacklisted) {
        return BUNNY_DB_OK;
    }

    /* Slow path: only reached when the fast path found nothing. A site
     * with no complex rules (today, for every existing user) returns here
     * after one cheap indexed SELECT -- no tag fetch, no matcher call. */
    bunny_db_tag_query_node_ptr_array complex_asts;
    bunny_db_result_t result = bunny_db_blacklist_fetch_complex_rules(db, site, &complex_asts);
    if (result != BUNNY_DB_OK) {
        return result;
    }
    if (complex_asts.count == 0) {
        bunny_db_tag_query_node_ptr_array_free(&complex_asts);
        return BUNNY_DB_OK;
    }

    bunny_db_string_list_t tag_names;
    result = bunny_db_post_get_tag_names(db, post_id, &tag_names);
    if (result != BUNNY_DB_OK) {
        bunny_db_blacklist_free_rule_asts(&complex_asts);
        return result;
    }
    for (size_t i = 0; i < complex_asts.count && !*out_is_blacklisted; i++) {
        if (bunny_tag_query_matches(complex_asts.items[i], (const char *const *)tag_names.items, tag_names.count)) {
            *out_is_blacklisted = true;
        }
    }
    bunny_db_string_list_free(&tag_names);
    bunny_db_blacklist_free_rule_asts(&complex_asts);
    return BUNNY_DB_OK;
}
