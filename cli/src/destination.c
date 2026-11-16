#include "destination.h"

#include <bunny_core/core.h>

#include <stdbool.h>
#include <stdio.h>
#include <string.h>

static bool is_reserved_artist_char(char c)
{
    return c == '\\' || c == '/' || c == ':' || c == '*' || c == '?' || c == '"' || c == '<' || c == '>' || c == '|';
}

static bool is_ascii_space(char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

/* Trims leading/trailing ASCII whitespace from `s` into `scratch` (sized
 * `scratch_size`) and returns it -- used for the "trim then check emptiness"
 * step DownloadManager._sanitizePoolName does in Dart before ever calling
 * the real sanitizer, which this mirrors in bunny_cli_destination_for
 * below. NULL `s` behaves like an empty string. */
static const char *trim_ascii(const char *s, char *scratch, size_t scratch_size)
{
    if (!s) {
        scratch[0] = '\0';
        return scratch;
    }
    while (*s && is_ascii_space(*s)) {
        s++;
    }
    size_t len = strlen(s);
    while (len > 0 && is_ascii_space(s[len - 1])) {
        len--;
    }
    size_t copy_len = len < scratch_size - 1 ? len : scratch_size - 1;
    memcpy(scratch, s, copy_len);
    scratch[copy_len] = '\0';
    return scratch;
}

/* Mirrors DownloadManager._sanitizeArtist exactly -- split on ", ", trim
 * each segment, drop empties, replace each segment's own reserved
 * characters with '_' (non-ASCII untouched, deliberately -- artist names
 * never go through bunny_sanitize_filename_segment at all, see that
 * function's own doc comment for why), join what's left with '/'.
 * "unknown" if nothing is left after all that. */
static void sanitize_artist(const char *artist, char *out, size_t out_size)
{
    if (!artist || !*artist) {
        snprintf(out, out_size, "unknown");
        return;
    }

    size_t out_len = 0;
    bool any_segment = false;
    const char *cursor = artist;

    while (cursor) {
        const char *comma = strstr(cursor, ", ");
        const char *segment_end = comma ? comma : cursor + strlen(cursor);

        const char *start = cursor;
        while (start < segment_end && is_ascii_space(*start)) {
            start++;
        }
        const char *end = segment_end;
        while (end > start && is_ascii_space(*(end - 1))) {
            end--;
        }

        if (end > start) {
            if (any_segment && out_len + 1 < out_size) {
                out[out_len++] = '/';
            }
            for (const char *p = start; p < end && out_len + 1 < out_size; p++) {
                out[out_len++] = is_reserved_artist_char(*p) ? '_' : *p;
            }
            any_segment = true;
        }

        cursor = comma ? comma + 2 : NULL;
    }
    out[out_len] = '\0';

    if (!any_segment) {
        snprintf(out, out_size, "unknown");
    }
}

void bunny_cli_destination_for(const char *artist, const char *ext, int64_t external_id, int64_t pool_id, const char *pool_name, int pool_page, char *out_folder, char *out_filename)
{
    const char *safe_ext = ext && *ext ? ext : "bin";

    if (pool_id > 0 && pool_page > 0) {
        char prefix[64];
        snprintf(prefix, sizeof(prefix), "pool_%lld - ", (long long)pool_id);
        size_t prefix_len = strlen(prefix);

        size_t max_len = bunny_filename_max_len();
        size_t title_budget = max_len > prefix_len ? max_len - prefix_len : 1;
        size_t title_buf_size = title_budget + 1 < BUNNY_CLI_DESTINATION_MAX ? title_budget + 1 : BUNNY_CLI_DESTINATION_MAX;

        char trim_scratch[BUNNY_CLI_DESTINATION_MAX];
        const char *trimmed_name = trim_ascii(pool_name, trim_scratch, sizeof(trim_scratch));
        if (!*trimmed_name) {
            trimmed_name = "untitled";
        }

        char title[BUNNY_CLI_DESTINATION_MAX];
        bunny_sanitize_filename_segment(trimmed_name, true, title, title_buf_size);

        snprintf(out_folder, BUNNY_CLI_DESTINATION_MAX, "%s%s", prefix, title);
        snprintf(out_filename, BUNNY_CLI_DESTINATION_MAX, "%lld - p%04d [%lld].%s", (long long)pool_id, pool_page, (long long)external_id, safe_ext);
        return;
    }

    sanitize_artist(artist, out_folder, BUNNY_CLI_DESTINATION_MAX);
    snprintf(out_filename, BUNNY_CLI_DESTINATION_MAX, "%lld.%s", (long long)external_id, safe_ext);
}
