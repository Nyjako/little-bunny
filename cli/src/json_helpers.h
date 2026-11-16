#ifndef BUNNY_CLI_JSON_HELPERS_H
#define BUNNY_CLI_JSON_HELPERS_H

#include <bunny_core/core.h>
#include <bunny_db/types.h>
#include <cJSON.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Same field set/names as the server's own post_to_json (server/src/routes_search.c)
 * -- deliberately kept identical so a script that already parses the
 * server's REST API output doesn't need a second shape for bunny_cli's.
 * Caller owns the returned cJSON* (cJSON_Delete it, or add it to a parent
 * that will). */
cJSON *bunny_cli_post_to_json(const bunny_db_post_t *post);

/* One post_to_json object per item, as a JSON array. */
cJSON *bunny_cli_post_list_to_json(const bunny_db_post_list_t *list);

/* referenced_pool_ids as a plain JSON array of numbers. */
cJSON *bunny_cli_pool_info_to_json(const bunny_core_pool_info_t *info);

/* A plain JSON array of strings -- used for blacklist dumps. */
cJSON *bunny_cli_string_list_to_json(const bunny_db_string_list_t *list);

/* One download_queue row, same field names as bunny_db_download_queue_item_t
 * itself (status printed via bunny_db_download_queue_status_to_string). */
cJSON *bunny_cli_download_queue_item_to_json(const bunny_db_download_queue_item_t *item);

/* One download_queue_item_to_json object per item, as a JSON array. */
cJSON *bunny_cli_download_queue_list_to_json(const bunny_db_download_queue_list_t *list);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_CLI_JSON_HELPERS_H */
