#include "bunny_bbcode/bbcode.h"

#include <ctype.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include <goblin/dyn_array.h>

GOBLIN_DYN_ARRAY_DECL(bb_block, bunny_doc_block_t)
GOBLIN_DYN_ARRAY_DECL(bb_run, bunny_doc_run_t)

/* ---- tiny local string helpers (deliberately not goblin/cstr.h -- this
 * parser only needs bunny_common for the shared bunny_doc_t model/free
 * function, same "no other bunny_* dependency" scoping libs/tag_query
 * already follows for its own pure parser). ---- */

static char *dup_slice(const char *s, size_t start, size_t end)
{
    size_t len = end > start ? end - start : 0;
    char *out = malloc(len + 1);
    if (!out) {
        return NULL;
    }
    if (len > 0) {
        memcpy(out, s + start, len);
    }
    out[len] = '\0';
    return out;
}

static char *dup_cstr(const char *s)
{
    return s ? dup_slice(s, 0, strlen(s)) : NULL;
}

/* A small growable buffer -- used by parse_runs to accumulate a run's plain
 * text across several non-contiguous source ranges (an unknown/stripped tag
 * in the middle splices its own bytes out without starting a new run). */
typedef struct
{
    char *data;
    size_t len;
    size_t cap;
} bb_buf_t;

static void bb_buf_init(bb_buf_t *b)
{
    b->data = NULL;
    b->len = 0;
    b->cap = 0;
}

static void bb_buf_free(bb_buf_t *b)
{
    free(b->data);
    bb_buf_init(b);
}

static void bb_buf_reserve(bb_buf_t *b, size_t extra)
{
    if (b->len + extra + 1 <= b->cap) {
        return;
    }
    size_t new_cap = b->cap ? b->cap : 64;
    while (new_cap < b->len + extra + 1) {
        new_cap *= 2;
    }
    char *grown = realloc(b->data, new_cap);
    if (!grown) {
        return; /* best-effort -- subsequent appends past capacity are dropped, never crashes */
    }
    b->data = grown;
    b->cap = new_cap;
}

/* Appends text[start,end), collapsing every '\n' to a plain space (the same
 * "single newline is a soft line break" rule applied to the whole block). */
static void bb_buf_append_range(bb_buf_t *b, const char *text, size_t start, size_t end)
{
    if (end <= start) {
        return;
    }
    size_t n = end - start;
    bb_buf_reserve(b, n);
    if (b->len + n + 1 > b->cap) {
        return; /* allocation failed in reserve -- drop rather than overflow */
    }
    for (size_t i = 0; i < n; i++) {
        char c = text[start + i];
        b->data[b->len + i] = (c == '\n') ? ' ' : c;
    }
    b->len += n;
    b->data[b->len] = '\0';
}

/* Hands ownership of the accumulated text to the caller and resets the
 * buffer to empty -- NULL if nothing was ever appended (caller treats that
 * as "no run to emit", matching push_run's own empty/NULL handling). */
static char *bb_buf_take(bb_buf_t *b)
{
    if (b->len == 0) {
        return NULL;
    }
    char *data = b->data;
    bb_buf_init(b);
    return data;
}

static bool is_ws(char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

static void trim_ws_inplace(char *s)
{
    size_t len = strlen(s);
    size_t start = 0;
    while (start < len && is_ws(s[start])) {
        start++;
    }
    size_t end = len;
    while (end > start && is_ws(s[end - 1])) {
        end--;
    }
    size_t trimmed_len = end - start;
    if (start > 0) {
        memmove(s, s + start, trimmed_len);
    }
    s[trimmed_len] = '\0';
}

static bool ci_equal_n(const char *a, size_t a_len, const char *b)
{
    size_t b_len = strlen(b);
    if (a_len != b_len) {
        return false;
    }
    for (size_t i = 0; i < a_len; i++) {
        if (tolower((unsigned char)a[i]) != tolower((unsigned char)b[i])) {
            return false;
        }
    }
    return true;
}

/* ---- tag scanning ---- */

/* text[open] must be '['. Finds the matching ']' with no nesting (BBCode
 * tags never nest brackets). Returns the index of ']', or (size_t)-1 if the
 * '[' is never closed (treated as a literal '[' by every caller). */
static size_t find_tag_close(const char *text, size_t open, size_t len)
{
    for (size_t i = open + 1; i < len; i++) {
        if (text[i] == '[') {
            return (size_t)-1; /* another '[' before this one closed -- not a tag */
        }
        if (text[i] == ']') {
            return i;
        }
    }
    return (size_t)-1;
}

typedef struct
{
    bool closing; /* true for "[/name]" */
    size_t name_start;
    size_t name_len;
    size_t attr_start; /* only meaningful when has_attr */
    size_t attr_len;
    bool has_attr;
} bb_tag_t;

/* Parses the tag at text[open..close] (inclusive brackets) into *out. */
static void parse_tag(const char *text, size_t open, size_t close, bb_tag_t *out)
{
    memset(out, 0, sizeof(*out));
    size_t p = open + 1;
    if (p < close && text[p] == '/') {
        out->closing = true;
        p++;
    }
    out->name_start = p;
    size_t eq = close;
    for (size_t i = p; i < close; i++) {
        if (text[i] == '=') {
            eq = i;
            break;
        }
    }
    out->name_len = eq - p;
    if (eq < close) {
        out->has_attr = true;
        out->attr_start = eq + 1;
        out->attr_len = close - out->attr_start;
    }
}

static bool tag_name_is(const bb_tag_t *tag, const char *text, const char *name)
{
    return ci_equal_n(text + tag->name_start, tag->name_len, name);
}

/* [h1]-[h6]: returns the level (1-6) or 0 if this isn't a heading tag. */
static int heading_level(const bb_tag_t *tag, const char *text)
{
    if (tag->name_len != 2) {
        return 0;
    }
    char c0 = (char)tolower((unsigned char)text[tag->name_start]);
    char c1 = text[tag->name_start + 1];
    if (c0 != 'h' || c1 < '1' || c1 > '6') {
        return 0;
    }
    return c1 - '0';
}

/* Searches forward from `from` for "[/name]" (case-insensitive). On a match,
 * sets *out_open to the '[' index and *out_end to just past the ']'. If
 * never found, treats the tag as unclosed through end-of-text (*out_open =
 * *out_end = len) -- malformed input degrades gracefully, never errors. */
static void find_matching_close(const char *text, size_t len, size_t from, const char *name, size_t *out_open, size_t *out_end)
{
    for (size_t i = from; i < len; i++) {
        if (text[i] != '[') {
            continue;
        }
        size_t close = find_tag_close(text, i, len);
        if (close == (size_t)-1) {
            continue;
        }
        bb_tag_t tag;
        parse_tag(text, i, close, &tag);
        if (tag.closing && tag_name_is(&tag, text, name)) {
            *out_open = i;
            *out_end = close + 1;
            return;
        }
    }
    *out_open = len;
    *out_end = len;
}

/* Same idea, for a closing heading tag of any level ("[/h1]".."[/h6]") --
 * Inkbunny's own writer only ever needs to match whatever heading tag was
 * opened, but a mismatched level (e.g. "[h2]...[/h3]") is tolerated the
 * same way a stray mismatched inline close is elsewhere in this file. */
static void find_matching_heading_close(const char *text, size_t len, size_t from, size_t *out_open, size_t *out_end)
{
    for (size_t i = from; i < len; i++) {
        if (text[i] != '[') {
            continue;
        }
        size_t close = find_tag_close(text, i, len);
        if (close == (size_t)-1) {
            continue;
        }
        bb_tag_t tag;
        parse_tag(text, i, close, &tag);
        if (tag.closing && heading_level(&tag, text) > 0) {
            *out_open = i;
            *out_end = close + 1;
            return;
        }
    }
    *out_open = len;
    *out_end = len;
}

/* ---- inline run parsing (within one block's own text) ---- */

static void push_run(bb_run_array *arr, bunny_doc_run_kind_t kind, char *text, char *url)
{
    if (!text || text[0] == '\0') {
        free(text);
        free(url);
        return;
    }
    bunny_doc_run_t run = {.kind = kind, .text = text, .url = url};
    if (!bb_run_array_push(arr, run)) {
        free(text);
        free(url);
    }
}

/* Flushes whatever has been accumulated in `pending` as one run of `style`,
 * then resets `pending` to empty. A no-op if nothing was accumulated. */
static void flush_pending(bb_run_array *arr, bb_buf_t *pending, bunny_doc_run_kind_t style)
{
    char *text = bb_buf_take(pending);
    if (text) {
        push_run(arr, style, text, NULL);
    }
}

static bool looks_like_url_start(const char *text, size_t pos, size_t len)
{
    size_t remaining = len - pos;
    if (remaining >= 7 && strncmp(text + pos, "http://", 7) == 0) {
        return true;
    }
    if (remaining >= 8 && strncmp(text + pos, "https://", 8) == 0) {
        return true;
    }
    return false;
}

/* Trailing punctuation that's almost always sentence punctuation, not part
 * of the URL itself -- mirrors the app's own RichMarkupText bare-URL
 * trimming (app/lib/util/rich_markup.dart). */
static bool is_url_trailing_punct(char c)
{
    return c == '.' || c == ',' || c == ';' || c == ':' || c == '!' || c == '?' || c == ')' || c == ']' || c == '}';
}

static size_t scan_bare_url_end(const char *text, size_t pos, size_t len)
{
    size_t end = pos;
    while (end < len && !is_ws(text[end]) && text[end] != '[') {
        end++;
    }
    while (end > pos && is_url_trailing_punct(text[end - 1])) {
        end--;
    }
    return end;
}

/* Strips any "[...]" tags out of a url/img body, keeping the rest verbatim
 * -- a BBCode-styled link label (e.g. "[url]http://x[/url]" is simple, but
 * "[url=...][b]label[/b][/url]" shows up occasionally) collapses to its
 * plain text rather than being recursively re-styled; the shared run model
 * has no way to carry both "this is a link" and "this is also bold" on one
 * run anyway. */
static char *strip_tags_to_plain(const char *text, size_t start, size_t end)
{
    char *out = malloc(end - start + 1);
    if (!out) {
        return NULL;
    }
    size_t o = 0;
    size_t i = start;
    while (i < end) {
        if (text[i] == '[') {
            size_t close = find_tag_close(text, i, end);
            if (close != (size_t)-1 && close < end) {
                i = close + 1;
                continue;
            }
        }
        out[o++] = text[i];
        i++;
    }
    out[o] = '\0';
    return out;
}

#define BB_STYLE_STACK_MAX 8

static void parse_runs(const char *text, size_t start, size_t end, bunny_doc_run_list_t *out)
{
    bb_run_array arr;
    bb_run_array_init(&arr);

    bunny_doc_run_kind_t stack[BB_STYLE_STACK_MAX];
    size_t stack_len = 0;
    bb_buf_t pending;
    bb_buf_init(&pending);
    size_t text_start = start;
    size_t pos = start;

    while (pos < end) {
        char c = text[pos];
        if (c == '[') {
            size_t close = find_tag_close(text, pos, end);
            if (close == (size_t)-1) {
                pos++;
                continue;
            }
            bb_tag_t tag;
            parse_tag(text, pos, close, &tag);

            bunny_doc_run_kind_t style = stack_len ? stack[stack_len - 1] : BUNNY_DOC_RUN_PLAIN;

            if (tag_name_is(&tag, text, "b") || tag_name_is(&tag, text, "i") || tag_name_is(&tag, text, "u")) {
                bunny_doc_run_kind_t kind = tag_name_is(&tag, text, "b") ? BUNNY_DOC_RUN_BOLD : tag_name_is(&tag, text, "i") ? BUNNY_DOC_RUN_ITALIC : BUNNY_DOC_RUN_UNDERLINE;
                bool will_push = !tag.closing && stack_len < BB_STYLE_STACK_MAX;
                bool will_pop = tag.closing && stack_len && stack[stack_len - 1] == kind;
                bb_buf_append_range(&pending, text, text_start, pos);
                if (will_push || will_pop) {
                    /* An actual style change -- flush whatever was pending
                     * under the OLD style before switching. */
                    flush_pending(&arr, &pending, style);
                    if (will_push) {
                        stack[stack_len++] = kind;
                    } else {
                        stack_len--;
                    }
                }
                /* else: a stray/mismatched close (or a stack-depth
                 * overflow on open) -- same as an unknown tag, spliced out
                 * without flushing, never crashes. */
                pos = close + 1;
                text_start = pos;
                continue;
            }

            if (!tag.closing && (tag_name_is(&tag, text, "url") || tag_name_is(&tag, text, "img"))) {
                bb_buf_append_range(&pending, text, text_start, pos);
                flush_pending(&arr, &pending, style);
                bool is_img = tag_name_is(&tag, text, "img");
                char *attr_url = tag.has_attr ? dup_slice(text, tag.attr_start, tag.attr_start + tag.attr_len) : NULL;

                size_t inner_open, inner_close_end;
                find_matching_close(text, end, close + 1, is_img ? "img" : "url", &inner_open, &inner_close_end);
                char *label = strip_tags_to_plain(text, close + 1, inner_open);
                if (label) {
                    trim_ws_inplace(label);
                }

                char *final_url = attr_url ? attr_url : dup_cstr(label && label[0] != '\0' ? label : "");
                char *final_text = (label && label[0] != '\0') ? label : dup_cstr(final_url);
                if (label && label != final_text) {
                    free(label);
                }
                push_run(&arr, BUNNY_DOC_RUN_URL, final_text, final_url);

                pos = inner_close_end;
                text_start = pos;
                continue;
            }

            /* Unknown/unsupported tag (including a stray mismatched close,
             * e.g. a lone "[/spoiler]") -- splice it out of `pending`
             * without flushing, so the text before and after it merges
             * into one run instead of fragmenting around every stripped
             * tag. */
            bb_buf_append_range(&pending, text, text_start, pos);
            pos = close + 1;
            text_start = pos;
            continue;
        }

        if (looks_like_url_start(text, pos, end)) {
            size_t url_end = scan_bare_url_end(text, pos, end);
            if (url_end > pos) {
                bunny_doc_run_kind_t style = stack_len ? stack[stack_len - 1] : BUNNY_DOC_RUN_PLAIN;
                bb_buf_append_range(&pending, text, text_start, pos);
                flush_pending(&arr, &pending, style);
                char *url = dup_slice(text, pos, url_end);
                char *url_copy = dup_cstr(url);
                push_run(&arr, BUNNY_DOC_RUN_URL, url, url_copy);
                pos = url_end;
                text_start = pos;
                continue;
            }
        }

        pos++;
    }

    bb_buf_append_range(&pending, text, text_start, end);
    bunny_doc_run_kind_t style = stack_len ? stack[stack_len - 1] : BUNNY_DOC_RUN_PLAIN;
    flush_pending(&arr, &pending, style);
    bb_buf_free(&pending);

    out->items = arr.items;
    out->count = arr.count;
}

/* ---- block parsing ---- */

static bool block_tag_at(const char *text, size_t pos, size_t len, bool *out_is_list, int *out_heading_level, size_t *out_tag_close)
{
    if (pos >= len || text[pos] != '[') {
        return false;
    }
    size_t close = find_tag_close(text, pos, len);
    if (close == (size_t)-1) {
        return false;
    }
    bb_tag_t tag;
    parse_tag(text, pos, close, &tag);
    if (tag.closing) {
        return false;
    }
    if (tag_name_is(&tag, text, "list")) {
        *out_is_list = true;
        *out_heading_level = 0;
        *out_tag_close = close;
        return true;
    }
    int level = heading_level(&tag, text);
    if (level > 0) {
        *out_is_list = false;
        *out_heading_level = level;
        *out_tag_close = close;
        return true;
    }
    return false;
}

static void parse_list_block(const char *text, size_t items_start, size_t items_end, bb_block_array *out)
{
    size_t p = items_start;
    while (p < items_end) {
        while (p < items_end && is_ws(text[p])) {
            p++;
        }
        if (p >= items_end || text[p] != '[') {
            p++;
            continue;
        }
        size_t close = find_tag_close(text, p, items_end);
        if (close == (size_t)-1) {
            break;
        }
        bb_tag_t tag;
        parse_tag(text, p, close, &tag);
        if (tag.closing || !tag_name_is(&tag, text, "*")) {
            p = close + 1;
            continue;
        }
        size_t item_start = close + 1;
        size_t item_end = items_end;
        for (size_t i = item_start; i < items_end; i++) {
            if (text[i] != '[') {
                continue;
            }
            size_t c2 = find_tag_close(text, i, items_end);
            if (c2 == (size_t)-1) {
                continue;
            }
            bb_tag_t next_tag;
            parse_tag(text, i, c2, &next_tag);
            if (!next_tag.closing && tag_name_is(&next_tag, text, "*")) {
                item_end = i;
                break;
            }
        }
        /* item_end sits right at the next "[*]"/"[/list]" tag -- trim the
         * whitespace run immediately before it (almost always just the
         * newline the author put before the next marker), which is a
         * boundary artifact, not meaningful trailing content. */
        while (item_end > item_start && is_ws(text[item_end - 1])) {
            item_end--;
        }
        while (item_start < item_end && is_ws(text[item_start])) {
            item_start++;
        }
        bunny_doc_block_t block = {.kind = BUNNY_DOC_BLOCK_LIST_ITEM, .heading_level = 0};
        parse_runs(text, item_start, item_end, &block.runs);
        if (block.runs.count > 0) {
            bb_block_array_push(out, block);
        } else {
            free(block.runs.items);
        }
        p = item_end;
    }
}

static void parse_blocks(const char *text, size_t len, bb_block_array *out)
{
    size_t pos = 0;
    while (pos < len) {
        while (pos < len && is_ws(text[pos])) {
            pos++;
        }
        if (pos >= len) {
            break;
        }

        bool is_list = false;
        int level = 0;
        size_t tag_close = 0;
        if (block_tag_at(text, pos, len, &is_list, &level, &tag_close)) {
            if (is_list) {
                size_t close_open, close_end;
                find_matching_close(text, len, tag_close + 1, "list", &close_open, &close_end);
                parse_list_block(text, tag_close + 1, close_open, out);
                pos = close_end;
            } else {
                size_t close_open, close_end;
                find_matching_heading_close(text, len, tag_close + 1, &close_open, &close_end);
                bunny_doc_block_t block = {.kind = BUNNY_DOC_BLOCK_HEADING, .heading_level = level};
                parse_runs(text, tag_close + 1, close_open, &block.runs);
                if (block.runs.count > 0) {
                    bb_block_array_push(out, block);
                } else {
                    free(block.runs.items);
                }
                pos = close_end;
            }
            continue;
        }

        size_t scan = pos;
        size_t para_end = len;
        while (scan < len) {
            if (text[scan] == '\n' && scan + 1 < len && text[scan + 1] == '\n') {
                para_end = scan;
                break;
            }
            if (text[scan] == '[') {
                bool tmp_is_list = false;
                int tmp_level = 0;
                size_t tmp_close = 0;
                if (block_tag_at(text, scan, len, &tmp_is_list, &tmp_level, &tmp_close)) {
                    para_end = scan;
                    break;
                }
            }
            scan++;
        }

        bunny_doc_block_t block = {.kind = BUNNY_DOC_BLOCK_PARAGRAPH, .heading_level = 0};
        parse_runs(text, pos, para_end, &block.runs);
        if (block.runs.count > 0) {
            bb_block_array_push(out, block);
        } else {
            free(block.runs.items);
        }

        pos = para_end;
        while (pos < len && text[pos] == '\n') {
            pos++;
        }
    }
}

bunny_bbcode_result_t bunny_bbcode_parse(const char *bbcode, bunny_doc_t *out_doc)
{
    if (!bbcode || !out_doc) {
        return BUNNY_BBCODE_ERR_INVALID_ARG;
    }
    memset(out_doc, 0, sizeof(*out_doc));

    /* Normalize line endings into a mutable working copy -- "\r\n"/"\r"
     * both become "\n" so every scan above only ever needs to look for
     * '\n'. */
    size_t src_len = strlen(bbcode);
    char *normalized = malloc(src_len + 1);
    if (!normalized) {
        return BUNNY_BBCODE_ERR_INVALID_ARG;
    }
    size_t o = 0;
    for (size_t i = 0; i < src_len; i++) {
        if (bbcode[i] == '\r') {
            normalized[o++] = '\n';
            if (i + 1 < src_len && bbcode[i + 1] == '\n') {
                i++;
            }
        } else {
            normalized[o++] = bbcode[i];
        }
    }
    normalized[o] = '\0';

    bb_block_array arr;
    bb_block_array_init(&arr);
    parse_blocks(normalized, o, &arr);
    free(normalized);

    out_doc->items = arr.items;
    out_doc->count = arr.count;
    return BUNNY_BBCODE_OK;
}
