/* See sync.c's own top-of-file comment for why timegm needs this defined
 * before any system header pulls in <features.h>. */
#define _DEFAULT_SOURCE

#include "bunny_core/core.h"

#include <bunny_common/json.h>
#include <cJSON.h>
#include <goblin/cstr.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "internal.h"

/* How long a cached report is served before bunny_core_get_stats_report
 * recomputes it -- each section is a full-table aggregate (see
 * bunny_db_top_favorited_tags/top_used_tags/top_favorited_pools/
 * top_viewed_searches), so this is a real tradeoff between staleness and
 * cost, not just a cosmetic default. 24h matches how infrequently this
 * report's inputs (favorites, pool membership, search view counts) actually
 * shift in a way worth re-ranking for. */
#define BUNNY_CORE_STATS_REPORT_TTL_SECONDS (24 * 3600)

/* Each merged section (top_favorited_tags/top_used_tags/top_viewed_searches)
 * keeps this many entries after combining both sites' own top results --
 * top_pools (e621-only, no merge) uses it directly as its db-layer limit. */
#define BUNNY_CORE_STATS_REPORT_SECTION_LIMIT 20

#ifdef _WIN32
#define bunny_stats_timegm _mkgmtime
#else
#define bunny_stats_timegm timegm
#endif

static char *prefixed_name(const char *site_label, const char *name)
{
    size_t len = strlen(site_label) + 2 + strlen(name) + 1;
    char *out = malloc(len);
    if (!out) {
        return NULL;
    }
    snprintf(out, len, "%s: %s", site_label, name);
    return out;
}

static int compare_tag_stat_desc(const void *a, const void *b)
{
    const bunny_db_tag_stat_t *stat_a = a;
    const bunny_db_tag_stat_t *stat_b = b;
    if (stat_b->count != stat_a->count) {
        return stat_b->count - stat_a->count;
    }
    return strcmp(stat_a->name, stat_b->name);
}

/* Combines `e621_list`/`inkbunny_list` (each already site-scoped) into one
 * list, prefixing every entry's name with its site so the same tag/label
 * text on both sites can't collide, sorted by count descending and
 * truncated to `limit`. Frees both inputs; the caller owns `*out_merged`. */
static void merge_site_scoped_stats(bunny_db_tag_stat_list_t *e621_list, bunny_db_tag_stat_list_t *inkbunny_list, int limit, bunny_db_tag_stat_list_t *out_merged)
{
    size_t total = e621_list->count + inkbunny_list->count;
    bunny_db_tag_stat_t *merged = total > 0 ? malloc(total * sizeof(bunny_db_tag_stat_t)) : NULL;

    size_t idx = 0;
    for (size_t i = 0; i < e621_list->count; i++) {
        merged[idx].name = prefixed_name("e621", e621_list->items[i].name);
        merged[idx].count = e621_list->items[i].count;
        idx++;
    }
    for (size_t i = 0; i < inkbunny_list->count; i++) {
        merged[idx].name = prefixed_name("inkbunny", inkbunny_list->items[i].name);
        merged[idx].count = inkbunny_list->items[i].count;
        idx++;
    }
    bunny_db_tag_stat_list_free(e621_list);
    bunny_db_tag_stat_list_free(inkbunny_list);

    if (total > 0) {
        qsort(merged, total, sizeof(bunny_db_tag_stat_t), compare_tag_stat_desc);
    }

    size_t kept = total < (size_t)limit ? total : (size_t)limit;
    for (size_t i = kept; i < total; i++) {
        free(merged[i].name);
    }

    out_merged->items = merged;
    out_merged->count = kept;
}

void bunny_core_stats_report_free(bunny_core_stats_report_t *report)
{
    if (!report) {
        return;
    }
    bunny_db_tag_stat_list_free(&report->top_favorited_tags);
    bunny_db_tag_stat_list_free(&report->top_used_tags);
    bunny_db_tag_stat_list_free(&report->top_pools);
    bunny_db_tag_stat_list_free(&report->top_viewed_searches);
    free(report->computed_at);
    memset(report, 0, sizeof(*report));
}

static cJSON *tag_stat_list_to_json(const bunny_db_tag_stat_list_t *list)
{
    cJSON *array = cJSON_CreateArray();
    for (size_t i = 0; i < list->count; i++) {
        cJSON *item = cJSON_CreateObject();
        cJSON_AddStringToObject(item, "name", list->items[i].name);
        cJSON_AddNumberToObject(item, "count", list->items[i].count);
        cJSON_AddItemToArray(array, item);
    }
    return array;
}

static char *serialize_report(const bunny_core_stats_report_t *report)
{
    cJSON *root = cJSON_CreateObject();
    cJSON_AddItemToObject(root, "top_favorited_tags", tag_stat_list_to_json(&report->top_favorited_tags));
    cJSON_AddItemToObject(root, "top_used_tags", tag_stat_list_to_json(&report->top_used_tags));
    cJSON_AddItemToObject(root, "top_pools", tag_stat_list_to_json(&report->top_pools));
    cJSON_AddItemToObject(root, "top_viewed_searches", tag_stat_list_to_json(&report->top_viewed_searches));
    char *json = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    return json;
}

static void tag_stat_list_from_json(const cJSON *array, bunny_db_tag_stat_list_t *out_list)
{
    memset(out_list, 0, sizeof(*out_list));
    if (!cJSON_IsArray(array)) {
        return;
    }
    size_t count = (size_t)cJSON_GetArraySize(array);
    if (count == 0) {
        return;
    }
    bunny_db_tag_stat_t *items = malloc(count * sizeof(bunny_db_tag_stat_t));
    if (!items) {
        return;
    }
    size_t i = 0;
    const cJSON *entry;
    cJSON_ArrayForEach(entry, array)
    {
        const char *name = bunny_json_get_string_or(entry, "name", "");
        items[i].name = goblin_copy_cstr(name);
        items[i].count = bunny_json_get_int_or(entry, "count", 0);
        i++;
    }
    out_list->items = items;
    out_list->count = count;
}

static void deserialize_report(const char *json, bunny_core_stats_report_t *out_report)
{
    memset(out_report, 0, sizeof(*out_report));
    cJSON *root = cJSON_Parse(json);
    if (!root) {
        return;
    }
    tag_stat_list_from_json(cJSON_GetObjectItemCaseSensitive(root, "top_favorited_tags"), &out_report->top_favorited_tags);
    tag_stat_list_from_json(cJSON_GetObjectItemCaseSensitive(root, "top_used_tags"), &out_report->top_used_tags);
    tag_stat_list_from_json(cJSON_GetObjectItemCaseSensitive(root, "top_pools"), &out_report->top_pools);
    tag_stat_list_from_json(cJSON_GetObjectItemCaseSensitive(root, "top_viewed_searches"), &out_report->top_viewed_searches);
    cJSON_Delete(root);
}

static char *current_timestamp_iso8601(void)
{
    time_t now = time(NULL);
    struct tm tm_utc;
#ifdef _WIN32
    gmtime_s(&tm_utc, &now);
#else
    gmtime_r(&now, &tm_utc);
#endif
    char buf[32];
    strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &tm_utc);
    return goblin_copy_cstr(buf);
}

/* True when `computed_at` (an ISO 8601 UTC timestamp) is further in the past
 * than the cache TTL, or can't be parsed at all -- an unparseable value
 * shouldn't be able to wedge the report into never refreshing. */
static bool report_is_stale(const char *computed_at)
{
    if (!computed_at) {
        return true;
    }
    int year, month, day, hour, min, sec;
    if (sscanf(computed_at, "%d-%d-%dT%d:%d:%d", &year, &month, &day, &hour, &min, &sec) != 6) {
        return true;
    }
    struct tm tm_computed;
    memset(&tm_computed, 0, sizeof(tm_computed));
    tm_computed.tm_year = year - 1900;
    tm_computed.tm_mon = month - 1;
    tm_computed.tm_mday = day;
    tm_computed.tm_hour = hour;
    tm_computed.tm_min = min;
    tm_computed.tm_sec = sec;
    time_t computed = bunny_stats_timegm(&tm_computed);
    return difftime(time(NULL), computed) > BUNNY_CORE_STATS_REPORT_TTL_SECONDS;
}

bunny_core_result_t bunny_core_refresh_stats_report(bunny_core_t *core, bunny_core_stats_report_t *out_report)
{
    if (!core || !out_report) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    memset(out_report, 0, sizeof(*out_report));

    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);

    bunny_db_tag_stat_list_t e621_fav, inkbunny_fav;
    bunny_db_top_favorited_tags(read_db, BUNNY_DB_SITE_E621, BUNNY_CORE_STATS_REPORT_SECTION_LIMIT, &e621_fav);
    bunny_db_top_favorited_tags(read_db, BUNNY_DB_SITE_INKBUNNY, BUNNY_CORE_STATS_REPORT_SECTION_LIMIT, &inkbunny_fav);
    merge_site_scoped_stats(&e621_fav, &inkbunny_fav, BUNNY_CORE_STATS_REPORT_SECTION_LIMIT, &out_report->top_favorited_tags);

    bunny_db_tag_stat_list_t e621_used, inkbunny_used;
    bunny_db_top_used_tags(read_db, BUNNY_DB_SITE_E621, BUNNY_CORE_STATS_REPORT_SECTION_LIMIT, &e621_used);
    bunny_db_top_used_tags(read_db, BUNNY_DB_SITE_INKBUNNY, BUNNY_CORE_STATS_REPORT_SECTION_LIMIT, &inkbunny_used);
    merge_site_scoped_stats(&e621_used, &inkbunny_used, BUNNY_CORE_STATS_REPORT_SECTION_LIMIT, &out_report->top_used_tags);

    /* e621 only -- Inkbunny has no pool concept, nothing to merge. */
    bunny_db_top_favorited_pools(read_db, BUNNY_DB_SITE_E621, BUNNY_CORE_STATS_REPORT_SECTION_LIMIT, &out_report->top_pools);

    bunny_db_tag_stat_list_t e621_viewed, inkbunny_viewed;
    bunny_db_top_viewed_searches(read_db, BUNNY_DB_SITE_E621, BUNNY_CORE_STATS_REPORT_SECTION_LIMIT, &e621_viewed);
    bunny_db_top_viewed_searches(read_db, BUNNY_DB_SITE_INKBUNNY, BUNNY_CORE_STATS_REPORT_SECTION_LIMIT, &inkbunny_viewed);
    merge_site_scoped_stats(&e621_viewed, &inkbunny_viewed, BUNNY_CORE_STATS_REPORT_SECTION_LIMIT, &out_report->top_viewed_searches);

    bunny_core_db_read_unlock(core, slot);

    out_report->computed_at = current_timestamp_iso8601();

    char *json = serialize_report(out_report);
    bunny_core_db_lock(core);
    bunny_db_set_cached_stats_report(core->db, json, out_report->computed_at);
    bunny_core_db_unlock(core);
    free(json);

    return BUNNY_CORE_OK;
}

bunny_core_result_t bunny_core_get_cached_stats_report(bunny_core_t *core, bunny_core_stats_report_t *out_report, bool *out_has_cache, bool *out_is_stale)
{
    if (!core || !out_report || !out_has_cache || !out_is_stale) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    memset(out_report, 0, sizeof(*out_report));

    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    char *json = NULL;
    char *computed_at = NULL;
    bunny_db_get_cached_stats_report(read_db, &json, &computed_at);
    bunny_core_db_read_unlock(core, slot);

    if (!json) {
        *out_has_cache = false;
        *out_is_stale = true;
        free(computed_at);
        return BUNNY_CORE_OK;
    }

    *out_has_cache = true;
    *out_is_stale = report_is_stale(computed_at);
    deserialize_report(json, out_report);
    out_report->computed_at = computed_at;
    free(json);
    return BUNNY_CORE_OK;
}
