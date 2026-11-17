#include "bunny_core/core.h"

#include <bunny_bbcode/bbcode.h>
#include <bunny_common/download.h>
#include <bunny_epub/epub.h>

#include <ctype.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "internal.h"

bunny_core_result_t bunny_core_get_writing_doc(bunny_core_t *core, int64_t post_id, bunny_doc_t *out_doc)
{
    if (!core || !out_doc) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }

    bunny_db_post_t post;
    bunny_core_result_t result = bunny_core_post_get_by_id(core, post_id, &post);
    if (result != BUNNY_CORE_OK) {
        return result;
    }
    if (!post.writing || post.writing[0] == '\0') {
        bunny_db_post_free(&post);
        return BUNNY_CORE_ERR_NOT_FOUND;
    }

    bunny_bbcode_result_t parse_result = bunny_bbcode_parse(post.writing, out_doc);
    bunny_db_post_free(&post);
    return parse_result == BUNNY_BBCODE_OK ? BUNNY_CORE_OK : BUNNY_CORE_ERR_UNKNOWN;
}

/* Guesses a cover image's mimetype from its file extension -- bunny_db_post_t's
 * own `file_ext` (not a stored mimetype; Inkbunny's per-file mimetype only
 * exists on the richer post_files rows, not worth a second query just for
 * this). Defaults to "image/jpeg", Inkbunny's overwhelmingly common case,
 * rather than failing the whole epub build over an unrecognized extension. */
static bool ci_equal(const char *a, const char *b)
{
    while (*a && *b) {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) {
            return false;
        }
        a++;
        b++;
    }
    return *a == '\0' && *b == '\0';
}

static const char *mimetype_for_ext(const char *ext)
{
    if (!ext) {
        return "image/jpeg";
    }
    if (ci_equal(ext, "png")) {
        return "image/png";
    }
    if (ci_equal(ext, "gif")) {
        return "image/gif";
    }
    if (ci_equal(ext, "webp")) {
        return "image/webp";
    }
    return "image/jpeg";
}

typedef struct
{
    unsigned char *data;
    size_t len;
    size_t cap;
} fetch_buffer_t;

static int fetch_buffer_on_chunk(void *user_data, const void *data, size_t len)
{
    fetch_buffer_t *buf = user_data;
    if (buf->len + len > buf->cap) {
        size_t new_cap = buf->cap ? buf->cap * 2 : 65536;
        while (new_cap < buf->len + len) {
            new_cap *= 2;
        }
        unsigned char *grown = realloc(buf->data, new_cap);
        if (!grown) {
            return 1; /* abort the transfer -- caller sees BUNNY_HTTP_ERR_NETWORK */
        }
        buf->data = grown;
        buf->cap = new_cap;
    }
    memcpy(buf->data + buf->len, data, len);
    buf->len += len;
    return 0;
}

bunny_core_result_t bunny_core_build_writing_epub(bunny_core_t *core, int64_t post_id, const char *dest_path)
{
    if (!core || !dest_path) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }

    bunny_db_post_t post;
    bunny_core_result_t result = bunny_core_post_get_by_id(core, post_id, &post);
    if (result != BUNNY_CORE_OK) {
        return result;
    }
    if (!post.writing || post.writing[0] == '\0') {
        bunny_db_post_free(&post);
        return BUNNY_CORE_ERR_NOT_FOUND;
    }

    bunny_doc_t doc;
    bunny_bbcode_result_t parse_result = bunny_bbcode_parse(post.writing, &doc);
    if (parse_result != BUNNY_BBCODE_OK) {
        bunny_db_post_free(&post);
        return BUNNY_CORE_ERR_UNKNOWN;
    }

    fetch_buffer_t cover = {0};
    bool have_cover = false;
    if (post.file_url) {
        bunny_download_sink_t sink = {.on_chunk = fetch_buffer_on_chunk, .on_progress = NULL, .user_data = &cover};
        long status = 0;
        bunny_http_result_t fetch_result = bunny_download_fetch(post.file_url, NULL, 0, &sink, &status);
        have_cover = fetch_result == BUNNY_HTTP_OK && status == 200 && cover.len > 0;
    }

    bunny_epub_build_params_t params = {0};
    params.title = post.title && post.title[0] ? post.title : "Untitled";
    params.author = post.artist;
    params.doc = &doc;
    if (have_cover) {
        params.cover_image = cover.data;
        params.cover_image_len = cover.len;
        params.cover_mimetype = mimetype_for_ext(post.file_ext);
    }

    bunny_epub_result_t build_result = bunny_epub_build(&params, dest_path);

    free(cover.data);
    bunny_doc_free(&doc);
    bunny_db_post_free(&post);

    if (build_result == BUNNY_EPUB_OK) {
        return BUNNY_CORE_OK;
    }
    return have_cover || !post.file_url ? BUNNY_CORE_ERR_UNKNOWN : BUNNY_CORE_ERR_SITE;
}

bunny_core_result_t bunny_core_read_writing_epub(const char *path, bunny_doc_t *out_doc)
{
    if (!path || !out_doc) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_epub_result_t result = bunny_epub_read(path, out_doc, NULL);
    if (result == BUNNY_EPUB_OK) {
        return BUNNY_CORE_OK;
    }
    return result == BUNNY_EPUB_ERR_INVALID_ARG ? BUNNY_CORE_ERR_INVALID_ARG : BUNNY_CORE_ERR_UNKNOWN;
}
