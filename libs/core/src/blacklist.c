#include "bunny_core/core.h"

#include <e621/client.h>

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "internal.h"

bunny_core_result_t bunny_core_blacklist_list(bunny_core_t *core, bunny_db_site_t site, bunny_db_string_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_blacklist_list(read_db, site, out_list);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_blacklist_add(bunny_core_t *core, bunny_db_site_t site, const char *tag)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_blacklist_add(core->db, site, tag);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_blacklist_remove(bunny_core_t *core, bunny_db_site_t site, const char *tag)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_blacklist_remove(core->db, site, tag);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

/* Trims leading/trailing spaces, tabs, and a trailing \r (Windows-style line
 * endings in the raw multi-line field) from `line` in place. */
static void trim_line(char **line)
{
    while (**line == ' ' || **line == '\t') {
        (*line)++;
    }
    size_t len = strlen(*line);
    while (len > 0 && ((*line)[len - 1] == ' ' || (*line)[len - 1] == '\t' || (*line)[len - 1] == '\r')) {
        (*line)[--len] = '\0';
    }
}

bunny_core_result_t bunny_core_sync_e621_blacklist(bunny_core_t *core, bunny_core_blacklist_sync_stats_t *out_stats)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }

    e621_client_t *client = bunny_core_build_e621_client(core);
    if (!client) {
        return BUNNY_CORE_ERR_SITE;
    }

    char *raw = NULL;
    e621_result_t fetch_result = e621_get_blacklisted_tags(client, &raw);
    e621_client_destroy(client);
    if (fetch_result != E621_OK) {
        return BUNNY_CORE_ERR_SITE;
    }

    bunny_db_string_list_t existing;
    memset(&existing, 0, sizeof(existing));
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t list_result = bunny_db_blacklist_list(read_db, BUNNY_DB_SITE_E621, &existing);
    bunny_core_db_read_unlock(core, slot);
    if (list_result != BUNNY_DB_OK) {
        free(raw);
        return bunny_core_map_db_result(list_result);
    }

    /* No strtok_r here (not available on MSVC) -- walk the raw buffer
     * ourselves, splitting on '\n' and null-terminating each line in place. */
    int added = 0, already_present = 0, skipped_multi_tag = 0;
    char *cursor = raw;
    while (*cursor) {
        char *newline = strchr(cursor, '\n');
        if (newline) {
            *newline = '\0';
        }

        char *line = cursor;
        trim_line(&line);
        if (*line) {
            if (strchr(line, ' ')) {
                skipped_multi_tag++;
            } else {
                bool already = false;
                for (size_t i = 0; i < existing.count; i++) {
                    if (strcmp(existing.items[i], line) == 0) {
                        already = true;
                        break;
                    }
                }
                if (already) {
                    already_present++;
                } else {
                    bunny_core_db_lock(core);
                    bunny_db_blacklist_add(core->db, BUNNY_DB_SITE_E621, line);
                    bunny_core_db_unlock(core);
                    added++;
                }
            }
        }

        if (!newline) {
            break;
        }
        cursor = newline + 1;
    }

    bunny_db_string_list_free(&existing);
    free(raw);

    if (out_stats) {
        out_stats->added = added;
        out_stats->already_present = already_present;
        out_stats->skipped_multi_tag = skipped_multi_tag;
    }
    return BUNNY_CORE_OK;
}
