#ifndef BUNNY_CLI_DESTINATION_H
#define BUNNY_CLI_DESTINATION_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* A destination's folder/filename never exceeds this -- generous for an
 * artist-chain folder (several artist names deep) or a pool title, well
 * above bunny_filename_max_len()'s own 200-byte segment budget. */
#define BUNNY_CLI_DESTINATION_MAX 512

/* Mirrors DownloadManager._destinationFor (app/lib/services/download_manager.dart)
 * byte-for-byte, so a file bunny_cli downloads lands exactly where the app
 * itself already expects to find it, and vice versa -- same folder/filename
 * scheme, same sanitization rules, same pool-vs-artist branching:
 *   - pool_id > 0 && pool_page > 0: "pool_<id> - <sanitized title>" folder,
 *     "<id> - p<page, 4-digit> [<external_id>].<ext>" filename.
 *   - otherwise: one nested folder level per artist in `artist` (a
 *     ", "-joined list, same as the post's own `artist` field already is --
 *     non-artist tags are filtered out well before this ever sees it, at
 *     the C sync layer), "<external_id>.<ext>" filename.
 * Writes NUL-terminated results into out_folder/out_filename, both at
 * least BUNNY_CLI_DESTINATION_MAX bytes; `ext`/`pool_name` may be NULL. */
void bunny_cli_destination_for(const char *artist, const char *ext, int64_t external_id, int64_t pool_id, const char *pool_name, int pool_page, char *out_folder, char *out_filename);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_CLI_DESTINATION_H */
