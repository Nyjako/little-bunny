#include "bunny_core/core.h"

#include <bunny_common/download.h>
#include <bunny_common/md5.h>
#include <bunny_common/thread.h>

#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <direct.h>
#define bunny_mkdir(path) _mkdir(path)
#else
#include <sys/stat.h>
#define bunny_mkdir(path) mkdir(path, 0755)
#endif

/* bunny_core_download_start/_poll/_release (M66) are deliberately stateless
 * with respect to bunny_core_t -- a pure network+filesystem operation with
 * no db/account dependency, unlike every other function in this file's own
 * header. Declared in core.h anyway purely for FFI discoverability (ffigen
 * only scans core.h/error.h/bunny_db/types.h, see bunny_core_ffi/
 * ffigen.yaml). A fixed-size slot table (not a dynamic handle allocator) is
 * enough -- DownloadQueueService (app/lib/services/download_queue_service.dart)
 * caps itself at 3 concurrent downloads; this leaves real headroom. */

#define BUNNY_CORE_DOWNLOAD_SLOT_COUNT 8
#define BUNNY_CORE_DOWNLOAD_ERROR_MESSAGE_CAP 256

typedef struct
{
    bool in_use;
    bool started; /* the background thread was actually spawned -- release() must join it */
    bunny_thread_t thread;
    bunny_mutex_t progress_lock; /* guards received/total/done/outcome/error_message below */
    int64_t received;
    int64_t total; /* -1 if unknown */
    bool done;
    bunny_core_download_outcome_t outcome;
    char error_message[BUNNY_CORE_DOWNLOAD_ERROR_MESSAGE_CAP];

    /* Owned copies -- the background thread needs these to outlive
     * whatever the caller passed in, which it has no guarantee of once
     * bunny_core_download_start returns. */
    char *file_url;
    char *dest_dir;
    char *filename;
    char *expected_md5; /* NULL if the caller passed NULL/empty */
    bunny_http_header_t *headers;
    size_t header_count;
} download_slot_t;

static download_slot_t g_slots[BUNNY_CORE_DOWNLOAD_SLOT_COUNT];
static bunny_mutex_t g_slots_lock;
static bool g_slots_lock_initialized = false;

static void ensure_slots_lock(void)
{
    /* Not itself safe against a genuine race -- fine, since every call into
     * this file happens through the single serialized dispatch pipe
     * bunny_core_ffi routes every bunny_core_* call through (see that
     * project's own doc comment); the download threads this spawns run
     * concurrently, but calls INTO bunny_core_download_start/_poll/_release
     * themselves never do. Same lazy-init-with-no-lock pattern bunny_common/
     * src/http.c's ensure_curl_global_init already relies on. */
    if (!g_slots_lock_initialized) {
        bunny_mutex_init(&g_slots_lock);
        g_slots_lock_initialized = true;
    }
}

static bool md5_hex_equal_ci(const char *a, const char *b)
{
    while (*a && *b) {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) {
            return false;
        }
        a++;
        b++;
    }
    return *a == *b;
}

static char *dup_string(const char *s)
{
    if (!s) {
        return NULL;
    }
    size_t len = strlen(s) + 1;
    char *copy = malloc(len);
    if (copy) {
        memcpy(copy, s, len);
    }
    return copy;
}

static char *join_path(const char *dir, const char *filename)
{
    size_t dir_len = strlen(dir);
    size_t filename_len = strlen(filename);
    char *result = malloc(dir_len + 1 + filename_len + 1);
    if (!result) {
        return NULL;
    }
    memcpy(result, dir, dir_len);
    result[dir_len] = '/';
    memcpy(result + dir_len + 1, filename, filename_len);
    result[dir_len + 1 + filename_len] = '\0';
    return result;
}

static int make_directory(const char *path)
{
    if (bunny_mkdir(path) == 0) {
        return 0;
    }
    return errno == EEXIST ? 0 : -1;
}

/* mkdir -p -- dest_dir may be several levels deep and none of it may exist
 * yet (e.g. a fresh install's first-ever download), matching what the Dart
 * code this replaces used to do via Directory(...).create(recursive: true). */
static int make_directories_recursive(const char *path)
{
    size_t len = strlen(path);
    if (len == 0 || len >= 1024) {
        return -1;
    }
    char buf[1024];
    memcpy(buf, path, len + 1);
    for (size_t i = 1; i < len; i++) {
        if (buf[i] == '/') {
            buf[i] = '\0';
            if (make_directory(buf) != 0) {
                return -1;
            }
            buf[i] = '/';
        }
    }
    return make_directory(buf);
}

/* True if a file already sits at path and either expected_md5 is NULL/empty
 * (nothing to verify -- trust as-is) or its contents actually match.
 * *out_size (if non-NULL) is always set to the file's size when it exists,
 * regardless of the checksum outcome -- the skip-fetch fast path below
 * needs it to report a real "received" byte count instead of leaving a
 * verified-on-first-look file's progress sitting at the slot's initial 0
 * forever (on_chunk/on_progress, this fast path's only other source of
 * that count, never run at all here). */
static bool file_matches_checksum(const char *path, const char *expected_md5, int64_t *out_size)
{
    FILE *f = fopen(path, "rb");
    if (!f) {
        return false;
    }
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    if (out_size) {
        *out_size = size >= 0 ? (int64_t)size : 0;
    }
    fseek(f, 0, SEEK_SET);
    if (!expected_md5 || !expected_md5[0]) {
        fclose(f);
        return true;
    }

    bunny_md5_ctx_t ctx;
    bunny_md5_init(&ctx);
    char buf[65536];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), f)) > 0) {
        bunny_md5_update(&ctx, buf, n);
    }
    fclose(f);

    char actual_hex[33];
    bunny_md5_final(&ctx, actual_hex);
    return md5_hex_equal_ci(actual_hex, expected_md5);
}

typedef struct
{
    FILE *file;
    bunny_md5_ctx_t md5;
    download_slot_t *slot;
    int64_t received; /* cumulative bytes written so far -- see on_chunk's own doc comment */
} download_write_ctx_t;

/* Also updates slot->received itself (under progress_lock), not just via
 * on_progress below -- curl only calls its xferinfo callback once it
 * decides enough time/data has passed (internally throttled, roughly a few
 * hundred ms), which a small/fast file can finish well within, meaning
 * on_progress might never fire at all for it. Without this, such a
 * download's progress stayed stuck at the slot's initial 0 for its entire
 * (short) lifetime -- not just coarse, but genuinely never updated -- which
 * is what the download queue screen's progress bar showing "0 B" for every
 * item actually was. */
static int on_chunk(void *user_data, const void *data, size_t len)
{
    download_write_ctx_t *ctx = (download_write_ctx_t *)user_data;
    bunny_md5_update(&ctx->md5, data, len);
    if (len > 0 && fwrite(data, 1, len, ctx->file) != len) {
        return 1;
    }
    ctx->received += (int64_t)len;
    bunny_mutex_lock(&ctx->slot->progress_lock);
    ctx->slot->received = ctx->received;
    bunny_mutex_unlock(&ctx->slot->progress_lock);
    return 0;
}

static void on_progress(void *user_data, int64_t received, int64_t total)
{
    download_write_ctx_t *ctx = (download_write_ctx_t *)user_data;
    bunny_mutex_lock(&ctx->slot->progress_lock);
    ctx->slot->received = received;
    ctx->slot->total = total;
    bunny_mutex_unlock(&ctx->slot->progress_lock);
}

static void finish_slot(download_slot_t *slot, bunny_core_download_outcome_t outcome, const char *error_message)
{
    bunny_mutex_lock(&slot->progress_lock);
    slot->outcome = outcome;
    if (error_message) {
        size_t cap = sizeof(slot->error_message);
        size_t len = strlen(error_message);
        if (len >= cap) {
            len = cap - 1;
        }
        memcpy(slot->error_message, error_message, len);
        slot->error_message[len] = '\0';
    } else {
        slot->error_message[0] = '\0';
    }
    slot->done = true;
    bunny_mutex_unlock(&slot->progress_lock);
}

static void *download_thread_main(void *arg)
{
    download_slot_t *slot = (download_slot_t *)arg;
    char *final_path = join_path(slot->dest_dir, slot->filename);
    char *tmp_path = NULL;

    if (!final_path) {
        finish_slot(slot, BUNNY_CORE_DOWNLOAD_FAILED, "out of memory");
        return NULL;
    }

    int64_t existing_size = 0;
    if (file_matches_checksum(final_path, slot->expected_md5, &existing_size)) {
        bunny_mutex_lock(&slot->progress_lock);
        slot->received = existing_size;
        slot->total = existing_size;
        bunny_mutex_unlock(&slot->progress_lock);
        finish_slot(slot, BUNNY_CORE_DOWNLOAD_VERIFIED, NULL);
        free(final_path);
        return NULL;
    }

    if (make_directories_recursive(slot->dest_dir) != 0) {
        finish_slot(slot, BUNNY_CORE_DOWNLOAD_FAILED, "failed to create destination directory");
        free(final_path);
        return NULL;
    }

    /* A per-slot suffix (this file's own, never reused while in_use) keeps
     * two concurrent downloads from ever racing on the same temp path, even
     * if they happened to target the same destination file -- matching the
     * reasoning the Dart code this replaces already documented for the
     * same scenario. */
    char tmp_filename[300];
    snprintf(tmp_filename, sizeof(tmp_filename), "%s.part%d", slot->filename, (int)(slot - g_slots));
    tmp_path = join_path(slot->dest_dir, tmp_filename);
    if (!tmp_path) {
        finish_slot(slot, BUNNY_CORE_DOWNLOAD_FAILED, "out of memory");
        free(final_path);
        return NULL;
    }

    FILE *tmp_file = fopen(tmp_path, "wb");
    if (!tmp_file) {
        char message[BUNNY_CORE_DOWNLOAD_ERROR_MESSAGE_CAP];
        snprintf(message, sizeof(message), "failed to open temp file: %s", strerror(errno));
        finish_slot(slot, BUNNY_CORE_DOWNLOAD_FAILED, message);
        free(final_path);
        free(tmp_path);
        return NULL;
    }

    download_write_ctx_t write_ctx;
    write_ctx.file = tmp_file;
    write_ctx.slot = slot;
    write_ctx.received = 0;
    bunny_md5_init(&write_ctx.md5);

    bunny_download_sink_t sink = {on_chunk, on_progress, &write_ctx};
    long status = 0;
    bunny_http_result_t fetch_result = bunny_download_fetch(slot->file_url, slot->headers, slot->header_count, &sink, &status);
    fclose(tmp_file);

    if (fetch_result != BUNNY_HTTP_OK) {
        finish_slot(slot, BUNNY_CORE_DOWNLOAD_FAILED, "network error");
        remove(tmp_path);
        free(final_path);
        free(tmp_path);
        return NULL;
    }
    if (status < 200 || status >= 300) {
        char message[BUNNY_CORE_DOWNLOAD_ERROR_MESSAGE_CAP];
        snprintf(message, sizeof(message), "HTTP %ld", status);
        finish_slot(slot, BUNNY_CORE_DOWNLOAD_FAILED, message);
        remove(tmp_path);
        free(final_path);
        free(tmp_path);
        return NULL;
    }

    char actual_md5[33];
    bunny_md5_final(&write_ctx.md5, actual_md5);

    if (rename(tmp_path, final_path) != 0) {
        char message[BUNNY_CORE_DOWNLOAD_ERROR_MESSAGE_CAP];
        snprintf(message, sizeof(message), "failed to move into place: %s", strerror(errno));
        finish_slot(slot, BUNNY_CORE_DOWNLOAD_FAILED, message);
        remove(tmp_path);
        free(final_path);
        free(tmp_path);
        return NULL;
    }

    bool verified = !slot->expected_md5 || !slot->expected_md5[0] || md5_hex_equal_ci(actual_md5, slot->expected_md5);
    finish_slot(slot, verified ? BUNNY_CORE_DOWNLOAD_VERIFIED : BUNNY_CORE_DOWNLOAD_CHECKSUM_MISMATCH, NULL);

    free(final_path);
    free(tmp_path);
    return NULL;
}

static void free_slot_owned_strings(download_slot_t *slot)
{
    free(slot->file_url);
    free(slot->dest_dir);
    free(slot->filename);
    free(slot->expected_md5);
    for (size_t i = 0; i < slot->header_count; i++) {
        free((void *)slot->headers[i].name);
        free((void *)slot->headers[i].value);
    }
    free(slot->headers);
    slot->file_url = NULL;
    slot->dest_dir = NULL;
    slot->filename = NULL;
    slot->expected_md5 = NULL;
    slot->headers = NULL;
    slot->header_count = 0;
}

bunny_core_result_t bunny_core_download_start(const char *file_url, const bunny_http_header_t *extra_headers, size_t extra_header_count, const char *dest_dir, const char *filename, const char *expected_md5_or_null, int64_t *out_handle)
{
    if (!file_url || !dest_dir || !filename || !out_handle) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }

    ensure_slots_lock();
    bunny_mutex_lock(&g_slots_lock);
    int found = -1;
    for (int i = 0; i < BUNNY_CORE_DOWNLOAD_SLOT_COUNT; i++) {
        if (!g_slots[i].in_use) {
            found = i;
            break;
        }
    }
    if (found < 0) {
        bunny_mutex_unlock(&g_slots_lock);
        return BUNNY_CORE_ERR_UNKNOWN;
    }
    download_slot_t *slot = &g_slots[found];
    memset(slot, 0, sizeof(*slot));
    slot->in_use = true;
    bunny_mutex_init(&slot->progress_lock);
    slot->total = -1;
    bunny_mutex_unlock(&g_slots_lock);

    slot->file_url = dup_string(file_url);
    slot->dest_dir = dup_string(dest_dir);
    slot->filename = dup_string(filename);
    slot->expected_md5 = (expected_md5_or_null && expected_md5_or_null[0]) ? dup_string(expected_md5_or_null) : NULL;
    if (extra_header_count > 0) {
        slot->headers = calloc(extra_header_count, sizeof(bunny_http_header_t));
        if (slot->headers) {
            for (size_t i = 0; i < extra_header_count; i++) {
                slot->headers[i].name = dup_string(extra_headers[i].name);
                slot->headers[i].value = dup_string(extra_headers[i].value);
            }
            slot->header_count = extra_header_count;
        }
    }

    if (!slot->file_url || !slot->dest_dir || !slot->filename) {
        free_slot_owned_strings(slot);
        bunny_mutex_destroy(&slot->progress_lock);
        bunny_mutex_lock(&g_slots_lock);
        slot->in_use = false;
        bunny_mutex_unlock(&g_slots_lock);
        return BUNNY_CORE_ERR_UNKNOWN;
    }

    if (bunny_thread_create(&slot->thread, download_thread_main, slot) != 0) {
        free_slot_owned_strings(slot);
        bunny_mutex_destroy(&slot->progress_lock);
        bunny_mutex_lock(&g_slots_lock);
        slot->in_use = false;
        bunny_mutex_unlock(&g_slots_lock);
        return BUNNY_CORE_ERR_UNKNOWN;
    }
    slot->started = true;

    *out_handle = (int64_t)found;
    return BUNNY_CORE_OK;
}

bunny_core_result_t bunny_core_download_poll(int64_t handle, int64_t *out_received, int64_t *out_total, bool *out_done, bunny_core_download_outcome_t *out_outcome, char *out_error_message, size_t out_error_message_cap)
{
    if (!out_received || !out_total || !out_done) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    /* Out-of-range and in-range-but-not-currently-tracked are the same
     * "I don't know this handle" case from a caller's perspective -- no
     * reason to make them tell the two apart. */
    if (handle < 0 || handle >= BUNNY_CORE_DOWNLOAD_SLOT_COUNT || !g_slots[handle].in_use) {
        return BUNNY_CORE_ERR_NOT_FOUND;
    }
    download_slot_t *slot = &g_slots[handle];

    bunny_mutex_lock(&slot->progress_lock);
    *out_received = slot->received;
    *out_total = slot->total;
    *out_done = slot->done;
    if (slot->done && out_outcome) {
        *out_outcome = slot->outcome;
    }
    if (slot->done && out_error_message && out_error_message_cap > 0) {
        size_t len = strlen(slot->error_message);
        if (len >= out_error_message_cap) {
            len = out_error_message_cap - 1;
        }
        memcpy(out_error_message, slot->error_message, len);
        out_error_message[len] = '\0';
    }
    bunny_mutex_unlock(&slot->progress_lock);

    return BUNNY_CORE_OK;
}

static void free_slot(download_slot_t *slot)
{
    free_slot_owned_strings(slot);
    bunny_mutex_destroy(&slot->progress_lock);
    ensure_slots_lock();
    bunny_mutex_lock(&g_slots_lock);
    slot->in_use = false;
    bunny_mutex_unlock(&g_slots_lock);
}

/* Joins the just-finished download thread, then frees its slot -- the
 * actual work bunny_core_download_release used to do synchronously itself.
 * Run on its own throwaway thread (never joined -- see
 * bunny_core_download_release below) so joining a thread that, in the
 * common case, has already finished (or is about to, with nothing left to
 * do but return -- see download_thread_main's own doc comment) never costs
 * the caller anything, however long it actually ends up taking. */
static void *reap_thread_main(void *arg)
{
    download_slot_t *slot = (download_slot_t *)arg;
    bunny_thread_join(slot->thread);
    free_slot(slot);
    return NULL;
}

/* Deliberately does not block on bunny_thread_join itself -- every call
 * into bunny_core_download_start/_poll/_release goes through the single
 * dispatch pipe bunny_core_ffi routes every bunny_core_* call through (see
 * ensure_slots_lock's own doc comment), shared across EVERY concurrently
 * downloading item (DownloadQueueService's own 3-at-a-time cap, M62) -- if
 * this joined synchronously, one item finishing would stall every other
 * still-downloading item's own poll calls for however long that join
 * took, visible as several downloads appearing to freeze together right
 * when one of them completes. Hands the join off to a short-lived,
 * detached reaper thread instead, so this returns (and the dispatch pipe
 * frees up for the next message, from any worker) immediately regardless
 * of how long the real join takes. The slot itself stays `in_use` until
 * the reaper actually finishes -- harmless: BUNNY_CORE_DOWNLOAD_SLOT_COUNT
 * (8) comfortably exceeds the 3 that are ever concurrently needed, so a
 * fresh bunny_core_download_start always finds a different free slot
 * rather than needing this exact one back immediately. */
void bunny_core_download_release(int64_t handle)
{
    if (handle < 0 || handle >= BUNNY_CORE_DOWNLOAD_SLOT_COUNT) {
        return;
    }
    download_slot_t *slot = &g_slots[handle];
    if (!slot->in_use) {
        return;
    }
    if (!slot->started) {
        /* bunny_thread_create itself never succeeded -- nothing to join. */
        free_slot(slot);
        return;
    }

    bunny_thread_t reaper;
    if (bunny_thread_create(&reaper, reap_thread_main, slot) != 0) {
        /* Reaper spawn failed (extremely unlikely) -- fall back to the old
         * blocking behavior rather than leaking this slot forever. */
        bunny_thread_join(slot->thread);
        free_slot(slot);
        return;
    }
    bunny_thread_detach(reaper);
}
