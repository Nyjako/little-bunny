#include "bunny_epub/epub.h"

#include "zip.h"

#include <ctype.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- a small growable string buffer, used while rendering/parsing XHTML ---- */

typedef struct
{
    char *data;
    size_t len;
    size_t cap;
} eb_buf_t;

static void eb_buf_init(eb_buf_t *b)
{
    b->data = NULL;
    b->len = 0;
    b->cap = 0;
}

static void eb_buf_free(eb_buf_t *b)
{
    free(b->data);
    eb_buf_init(b);
}

static void eb_buf_reserve(eb_buf_t *b, size_t extra)
{
    if (b->len + extra + 1 <= b->cap) {
        return;
    }
    size_t new_cap = b->cap ? b->cap : 256;
    while (new_cap < b->len + extra + 1) {
        new_cap *= 2;
    }
    char *grown = realloc(b->data, new_cap);
    if (!grown) {
        return; /* best-effort; appends past this point are dropped, never overflow */
    }
    b->data = grown;
    b->cap = new_cap;
}

static void eb_buf_append(eb_buf_t *b, const char *s, size_t n)
{
    if (n == 0) {
        return;
    }
    eb_buf_reserve(b, n);
    if (b->len + n + 1 > b->cap) {
        return;
    }
    memcpy(b->data + b->len, s, n);
    b->len += n;
    b->data[b->len] = '\0';
}

static void eb_buf_append_cstr(eb_buf_t *b, const char *s)
{
    eb_buf_append(b, s, strlen(s));
}

static const char *eb_buf_cstr(const eb_buf_t *b)
{
    return b->data ? b->data : "";
}

static char *dup_cstr(const char *s)
{
    if (!s) {
        return NULL;
    }
    size_t len = strlen(s);
    char *out = malloc(len + 1);
    if (!out) {
        return NULL;
    }
    memcpy(out, s, len + 1);
    return out;
}

/* ---- XML escaping ---- */

static void xml_escape_append(eb_buf_t *out, const char *s, bool escape_quotes)
{
    if (!s) {
        return;
    }
    for (const char *p = s; *p; p++) {
        switch (*p) {
            case '&':
                eb_buf_append_cstr(out, "&amp;");
                break;
            case '<':
                eb_buf_append_cstr(out, "&lt;");
                break;
            case '>':
                eb_buf_append_cstr(out, "&gt;");
                break;
            case '"':
                if (escape_quotes) {
                    eb_buf_append_cstr(out, "&quot;");
                } else {
                    eb_buf_append(out, p, 1);
                }
                break;
            default:
                eb_buf_append(out, p, 1);
        }
    }
}

static char *xml_unescape(const char *s, size_t start, size_t end)
{
    char *out = malloc(end - start + 1);
    if (!out) {
        return NULL;
    }
    size_t o = 0;
    size_t i = start;
    while (i < end) {
        if (s[i] == '&') {
            if (strncmp(s + i, "&amp;", 5) == 0) {
                out[o++] = '&';
                i += 5;
                continue;
            }
            if (strncmp(s + i, "&lt;", 4) == 0) {
                out[o++] = '<';
                i += 4;
                continue;
            }
            if (strncmp(s + i, "&gt;", 4) == 0) {
                out[o++] = '>';
                i += 4;
                continue;
            }
            if (strncmp(s + i, "&quot;", 6) == 0) {
                out[o++] = '"';
                i += 6;
                continue;
            }
            if (strncmp(s + i, "&apos;", 6) == 0) {
                out[o++] = '\'';
                i += 6;
                continue;
            }
        }
        out[o++] = s[i++];
    }
    out[o] = '\0';
    return out;
}

/* ---- rendering a bunny_doc_t to XHTML ---- */

static void render_runs(eb_buf_t *out, const bunny_doc_run_list_t *runs)
{
    for (size_t i = 0; i < runs->count; i++) {
        const bunny_doc_run_t *run = &runs->items[i];
        switch (run->kind) {
            case BUNNY_DOC_RUN_BOLD:
                eb_buf_append_cstr(out, "<b>");
                xml_escape_append(out, run->text, false);
                eb_buf_append_cstr(out, "</b>");
                break;
            case BUNNY_DOC_RUN_ITALIC:
                eb_buf_append_cstr(out, "<i>");
                xml_escape_append(out, run->text, false);
                eb_buf_append_cstr(out, "</i>");
                break;
            case BUNNY_DOC_RUN_UNDERLINE:
                eb_buf_append_cstr(out, "<u>");
                xml_escape_append(out, run->text, false);
                eb_buf_append_cstr(out, "</u>");
                break;
            case BUNNY_DOC_RUN_URL:
                eb_buf_append_cstr(out, "<a href=\"");
                xml_escape_append(out, run->url ? run->url : "", true);
                eb_buf_append_cstr(out, "\">");
                xml_escape_append(out, run->text, false);
                eb_buf_append_cstr(out, "</a>");
                break;
            case BUNNY_DOC_RUN_PLAIN:
            default:
                xml_escape_append(out, run->text, false);
                break;
        }
    }
}

static void render_body(eb_buf_t *out, const bunny_doc_t *doc)
{
    bool in_list = false;
    for (size_t i = 0; i < doc->count; i++) {
        const bunny_doc_block_t *block = &doc->items[i];
        if (block->kind == BUNNY_DOC_BLOCK_LIST_ITEM) {
            if (!in_list) {
                eb_buf_append_cstr(out, "<ul>\n");
                in_list = true;
            }
            eb_buf_append_cstr(out, "<li>");
            render_runs(out, &block->runs);
            eb_buf_append_cstr(out, "</li>\n");
            continue;
        }
        if (in_list) {
            eb_buf_append_cstr(out, "</ul>\n");
            in_list = false;
        }
        if (block->kind == BUNNY_DOC_BLOCK_HEADING) {
            int level = block->heading_level >= 1 && block->heading_level <= 6 ? block->heading_level : 1;
            char tag[5];
            snprintf(tag, sizeof(tag), "h%d", level);
            eb_buf_append_cstr(out, "<");
            eb_buf_append_cstr(out, tag);
            eb_buf_append_cstr(out, ">");
            render_runs(out, &block->runs);
            eb_buf_append_cstr(out, "</");
            eb_buf_append_cstr(out, tag);
            eb_buf_append_cstr(out, ">\n");
        } else {
            eb_buf_append_cstr(out, "<p>");
            render_runs(out, &block->runs);
            eb_buf_append_cstr(out, "</p>\n");
        }
    }
    if (in_list) {
        eb_buf_append_cstr(out, "</ul>\n");
    }
}

/* A readable, built-in stylesheet -- serif body text, comfortable line
 * height/margins, modestly styled headings. */
static const char *const BUNNY_EPUB_STYLE_CSS = "body { font-family: Georgia, \"Times New Roman\", serif; line-height: 1.6; margin: 5%; }\n"
                                                "h1, h2, h3, h4, h5, h6 { font-family: Georgia, \"Times New Roman\", serif; margin-top: 1.5em; margin-bottom: 0.5em; }\n"
                                                "p { margin: 0 0 1em 0; text-indent: 1.5em; }\n"
                                                "ul { margin: 0 0 1em 1.5em; padding: 0; }\n"
                                                "li { margin-bottom: 0.5em; }\n"
                                                "a { color: inherit; text-decoration: underline; }\n"
                                                ".cover { text-align: center; margin: 0; padding: 0; }\n"
                                                ".cover img { max-width: 100%; max-height: 100vh; }\n";

static const char *const BUNNY_EPUB_CONTAINER_XML = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                                                    "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">\n"
                                                    "  <rootfiles>\n"
                                                    "    <rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/>\n"
                                                    "  </rootfiles>\n"
                                                    "</container>\n";

static bunny_epub_result_t build_content_opf(const bunny_epub_build_params_t *params, eb_buf_t *out)
{
    eb_buf_append_cstr(out, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    eb_buf_append_cstr(out, "<package xmlns=\"http://www.idpf.org/2007/opf\" unique-identifier=\"BookId\" version=\"2.0\">\n");
    eb_buf_append_cstr(out, "  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:opf=\"http://www.idpf.org/2007/opf\">\n");
    eb_buf_append_cstr(out, "    <dc:title>");
    xml_escape_append(out, params->title, false);
    eb_buf_append_cstr(out, "</dc:title>\n");
    if (params->author) {
        eb_buf_append_cstr(out, "    <dc:creator>");
        xml_escape_append(out, params->author, false);
        eb_buf_append_cstr(out, "</dc:creator>\n");
    }
    eb_buf_append_cstr(out, "    <dc:language>en</dc:language>\n");
    eb_buf_append_cstr(out, "    <dc:identifier id=\"BookId\">bunny-epub:");
    xml_escape_append(out, params->title, false);
    eb_buf_append_cstr(out, "</dc:identifier>\n");
    if (params->cover_image) {
        eb_buf_append_cstr(out, "    <meta name=\"cover\" content=\"cover-image\"/>\n");
    }
    eb_buf_append_cstr(out, "  </metadata>\n");
    eb_buf_append_cstr(out, "  <manifest>\n");
    eb_buf_append_cstr(out, "    <item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>\n");
    eb_buf_append_cstr(out, "    <item id=\"style\" href=\"style.css\" media-type=\"text/css\"/>\n");
    eb_buf_append_cstr(out, "    <item id=\"text\" href=\"text.xhtml\" media-type=\"application/xhtml+xml\"/>\n");
    if (params->cover_image) {
        eb_buf_append_cstr(out, "    <item id=\"cover\" href=\"cover.xhtml\" media-type=\"application/xhtml+xml\"/>\n");
        eb_buf_append_cstr(out, "    <item id=\"cover-image\" href=\"cover-image.img\" media-type=\"");
        xml_escape_append(out, params->cover_mimetype, true);
        eb_buf_append_cstr(out, "\"/>\n");
    }
    eb_buf_append_cstr(out, "  </manifest>\n");
    eb_buf_append_cstr(out, "  <spine toc=\"ncx\">\n");
    if (params->cover_image) {
        eb_buf_append_cstr(out, "    <itemref idref=\"cover\"/>\n");
    }
    eb_buf_append_cstr(out, "    <itemref idref=\"text\"/>\n");
    eb_buf_append_cstr(out, "  </spine>\n");
    eb_buf_append_cstr(out, "</package>\n");
    return BUNNY_EPUB_OK;
}

static void build_toc_ncx(const bunny_epub_build_params_t *params, eb_buf_t *out)
{
    eb_buf_append_cstr(out, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    eb_buf_append_cstr(out, "<ncx xmlns=\"http://www.daisy.org/z3986/2005/ncx/\" version=\"2005-1\">\n");
    eb_buf_append_cstr(out, "  <head><meta name=\"dtb:uid\" content=\"bunny-epub\"/></head>\n");
    eb_buf_append_cstr(out, "  <docTitle><text>");
    xml_escape_append(out, params->title, false);
    eb_buf_append_cstr(out, "</text></docTitle>\n");
    eb_buf_append_cstr(out, "  <navMap>\n");
    eb_buf_append_cstr(out, "    <navPoint id=\"navpoint-1\" playOrder=\"1\">\n");
    eb_buf_append_cstr(out, "      <navLabel><text>");
    xml_escape_append(out, params->title, false);
    eb_buf_append_cstr(out, "</text></navLabel>\n");
    eb_buf_append_cstr(out, "      <content src=\"text.xhtml\"/>\n");
    eb_buf_append_cstr(out, "    </navPoint>\n");
    eb_buf_append_cstr(out, "  </navMap>\n");
    eb_buf_append_cstr(out, "</ncx>\n");
}

static void build_cover_xhtml(const bunny_epub_build_params_t *params, eb_buf_t *out)
{
    eb_buf_append_cstr(out, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    eb_buf_append_cstr(out, "<!DOCTYPE html>\n");
    eb_buf_append_cstr(out, "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>");
    xml_escape_append(out, params->title, false);
    eb_buf_append_cstr(out, "</title><link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\"/></head>\n");
    eb_buf_append_cstr(out, "<body class=\"cover\"><img src=\"cover-image.img\" alt=\"Cover\"/></body></html>\n");
}

static void build_text_xhtml(const bunny_epub_build_params_t *params, eb_buf_t *out)
{
    eb_buf_append_cstr(out, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    eb_buf_append_cstr(out, "<!DOCTYPE html>\n");
    eb_buf_append_cstr(out, "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>");
    xml_escape_append(out, params->title, false);
    eb_buf_append_cstr(out, "</title><link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\"/></head>\n<body>\n");
    render_body(out, params->doc);
    eb_buf_append_cstr(out, "</body></html>\n");
}

bunny_epub_result_t bunny_epub_build(const bunny_epub_build_params_t *params, const char *dest_path)
{
    if (!params || !params->title || !params->doc || !dest_path) {
        return BUNNY_EPUB_ERR_INVALID_ARG;
    }
    if (params->cover_image && !params->cover_mimetype) {
        return BUNNY_EPUB_ERR_INVALID_ARG;
    }

    bunny_zip_writer_t *zip = bunny_zip_writer_open(dest_path);
    if (!zip) {
        return BUNNY_EPUB_ERR_IO;
    }

    bool ok = true;
    /* "mimetype" must be the very first entry, stored uncompressed -- the
     * one hard requirement EPUB's OCF spec has on the ZIP container
     * itself. bunny_zip_writer_add always stores uncompressed, so only
     * the ordering matters here. */
    ok = ok && bunny_zip_writer_add(zip, "mimetype", (const unsigned char *)"application/epub+zip", strlen("application/epub+zip"));
    ok = ok && bunny_zip_writer_add(zip, "META-INF/container.xml", (const unsigned char *)BUNNY_EPUB_CONTAINER_XML, strlen(BUNNY_EPUB_CONTAINER_XML));
    ok = ok && bunny_zip_writer_add(zip, "OEBPS/style.css", (const unsigned char *)BUNNY_EPUB_STYLE_CSS, strlen(BUNNY_EPUB_STYLE_CSS));

    eb_buf_t opf;
    eb_buf_init(&opf);
    build_content_opf(params, &opf);
    ok = ok && bunny_zip_writer_add(zip, "OEBPS/content.opf", (const unsigned char *)eb_buf_cstr(&opf), opf.len);
    eb_buf_free(&opf);

    eb_buf_t ncx;
    eb_buf_init(&ncx);
    build_toc_ncx(params, &ncx);
    ok = ok && bunny_zip_writer_add(zip, "OEBPS/toc.ncx", (const unsigned char *)eb_buf_cstr(&ncx), ncx.len);
    eb_buf_free(&ncx);

    if (params->cover_image) {
        eb_buf_t cover_xhtml;
        eb_buf_init(&cover_xhtml);
        build_cover_xhtml(params, &cover_xhtml);
        ok = ok && bunny_zip_writer_add(zip, "OEBPS/cover.xhtml", (const unsigned char *)eb_buf_cstr(&cover_xhtml), cover_xhtml.len);
        eb_buf_free(&cover_xhtml);
        ok = ok && bunny_zip_writer_add(zip, "OEBPS/cover-image.img", params->cover_image, params->cover_image_len);
    }

    eb_buf_t text_xhtml;
    eb_buf_init(&text_xhtml);
    build_text_xhtml(params, &text_xhtml);
    ok = ok && bunny_zip_writer_add(zip, "OEBPS/text.xhtml", (const unsigned char *)eb_buf_cstr(&text_xhtml), text_xhtml.len);
    eb_buf_free(&text_xhtml);

    bool closed_ok = bunny_zip_writer_close(zip);
    return (ok && closed_ok) ? BUNNY_EPUB_OK : BUNNY_EPUB_ERR_IO;
}

/* ---- reading a bunny_doc_t back out of text.xhtml ---- */

static bool is_xml_ws(char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

/* Finds the end of the tag starting at s[open] (which must be '<'), i.e.
 * the index of its '>'. (size_t)-1 if never closed. Doesn't need to handle
 * '>' inside an attribute value (our own writer never emits one). */
static size_t find_close_gt(const char *s, size_t open, size_t len)
{
    for (size_t i = open + 1; i < len; i++) {
        if (s[i] == '>') {
            return i;
        }
    }
    return (size_t)-1;
}

/* Returns the lowercase tag name of s[open+1 .. close) (stopping at the
 * first space or '/'), e.g. "b", "a", "h2". */
static void tag_name(const char *s, size_t open, size_t close, char *out, size_t out_cap)
{
    size_t p = open + 1;
    if (p < close && s[p] == '/') {
        p++;
    }
    size_t o = 0;
    while (p < close && o + 1 < out_cap && !is_xml_ws(s[p]) && s[p] != '/' && s[p] != '>') {
        out[o++] = (char)tolower((unsigned char)s[p]);
        p++;
    }
    out[o] = '\0';
}

static bool tag_is_closing(const char *s, size_t open)
{
    return s[open + 1] == '/';
}

/* Extracts the `href` attribute value (already-written form, so it only
 * ever needs double quotes) from an opening "<a href="...">" tag. NULL if
 * absent. */
static char *extract_href(const char *s, size_t open, size_t close)
{
    const char *needle = "href=\"";
    for (size_t i = open; i + 6 < close; i++) {
        if (strncmp(s + i, needle, 6) == 0) {
            size_t value_start = i + 6;
            size_t value_end = value_start;
            while (value_end < close && s[value_end] != '"') {
                value_end++;
            }
            return xml_unescape(s, value_start, value_end);
        }
    }
    return NULL;
}

/* Parses the inline content of one block (between e.g. "<p>" and "</p>")
 * into a run list -- mirrors libs/bbcode's own run parser, but for the
 * small, well-formed HTML subset this project's own writer emits (never
 * malformed, never truly nested beyond one level), so it stays much
 * simpler: a plain accumulator with no "mismatched tag" tolerance needed. */
static void parse_inline_runs(const char *s, size_t start, size_t end, bunny_doc_run_list_t *out)
{
    typedef struct
    {
        bunny_doc_run_t *items;
        size_t count;
        size_t cap;
    } run_list_builder_t;
    run_list_builder_t runs = {0};

    eb_buf_t pending;
    eb_buf_init(&pending);
    size_t text_start = start;
    size_t pos = start;
    bunny_doc_run_kind_t current = BUNNY_DOC_RUN_PLAIN;

    while (pos < end) {
        if (s[pos] != '<') {
            pos++;
            continue;
        }
        size_t close = find_close_gt(s, pos, end);
        if (close == (size_t)-1) {
            pos++;
            continue;
        }
        char name[8];
        tag_name(s, pos, close, name, sizeof(name));
        bool closing = tag_is_closing(s, pos);

        if (strcmp(name, "b") == 0 || strcmp(name, "i") == 0 || strcmp(name, "u") == 0) {
            if (text_start < pos) {
                char *unescaped = xml_unescape(s, text_start, pos);
                eb_buf_append_cstr(&pending, unescaped ? unescaped : "");
                free(unescaped);
            }
            if (pending.len > 0) {
                bunny_doc_run_t run = {.kind = current, .text = eb_buf_cstr(&pending)[0] ? dup_cstr(eb_buf_cstr(&pending)) : NULL};
                if (run.text) {
                    if (runs.count == runs.cap) {
                        runs.cap = runs.cap ? runs.cap * 2 : 4;
                        runs.items = realloc(runs.items, runs.cap * sizeof(*runs.items));
                    }
                    runs.items[runs.count++] = run;
                }
                eb_buf_free(&pending);
            }
            current = closing ? BUNNY_DOC_RUN_PLAIN : (strcmp(name, "b") == 0 ? BUNNY_DOC_RUN_BOLD : strcmp(name, "i") == 0 ? BUNNY_DOC_RUN_ITALIC : BUNNY_DOC_RUN_UNDERLINE);
            pos = close + 1;
            text_start = pos;
            continue;
        }

        if (strcmp(name, "a") == 0 && !closing) {
            if (text_start < pos) {
                char *unescaped = xml_unescape(s, text_start, pos);
                eb_buf_append_cstr(&pending, unescaped ? unescaped : "");
                free(unescaped);
            }
            if (pending.len > 0) {
                bunny_doc_run_t run = {.kind = current, .text = dup_cstr(eb_buf_cstr(&pending))};
                if (runs.count == runs.cap) {
                    runs.cap = runs.cap ? runs.cap * 2 : 4;
                    runs.items = realloc(runs.items, runs.cap * sizeof(*runs.items));
                }
                runs.items[runs.count++] = run;
                eb_buf_free(&pending);
            }
            char *href = extract_href(s, pos, close);
            size_t a_close_open = end, a_close_end = end;
            for (size_t i = close + 1; i < end; i++) {
                if (s[i] != '<') {
                    continue;
                }
                size_t c2 = find_close_gt(s, i, end);
                if (c2 == (size_t)-1) {
                    continue;
                }
                char n2[8];
                tag_name(s, i, c2, n2, sizeof(n2));
                if (tag_is_closing(s, i) && strcmp(n2, "a") == 0) {
                    a_close_open = i;
                    a_close_end = c2 + 1;
                    break;
                }
            }
            char *label = xml_unescape(s, close + 1, a_close_open);
            bunny_doc_run_t run = {.kind = BUNNY_DOC_RUN_URL, .text = label, .url = href};
            if (runs.count == runs.cap) {
                runs.cap = runs.cap ? runs.cap * 2 : 4;
                runs.items = realloc(runs.items, runs.cap * sizeof(*runs.items));
            }
            runs.items[runs.count++] = run;
            pos = a_close_end;
            text_start = pos;
            continue;
        }

        /* Any other tag -- shouldn't appear in our own output, but skip
         * it without crashing rather than assume well-formedness blindly. */
        pos = close + 1;
        text_start = pos;
    }

    if (text_start < end) {
        char *unescaped = xml_unescape(s, text_start, end);
        eb_buf_append_cstr(&pending, unescaped ? unescaped : "");
        free(unescaped);
    }
    if (pending.len > 0) {
        bunny_doc_run_t run = {.kind = current, .text = dup_cstr(eb_buf_cstr(&pending))};
        if (runs.count == runs.cap) {
            runs.cap = runs.cap ? runs.cap * 2 : 4;
            runs.items = realloc(runs.items, runs.cap * sizeof(*runs.items));
        }
        runs.items[runs.count++] = run;
    }
    eb_buf_free(&pending);

    out->items = runs.items;
    out->count = runs.count;
}

static void parse_body_to_doc(const char *s, size_t start, size_t end, bunny_doc_t *out_doc)
{
    typedef struct
    {
        bunny_doc_block_t *items;
        size_t count;
        size_t cap;
    } block_list_builder_t;
    block_list_builder_t blocks = {0};

    size_t pos = start;
    while (pos < end) {
        while (pos < end && is_xml_ws(s[pos])) {
            pos++;
        }
        if (pos >= end || s[pos] != '<') {
            pos++;
            continue;
        }
        size_t close = find_close_gt(s, pos, end);
        if (close == (size_t)-1) {
            break;
        }
        char name[8];
        tag_name(s, pos, close, name, sizeof(name));
        if (tag_is_closing(s, pos)) {
            pos = close + 1;
            continue;
        }

        bunny_doc_block_kind_t kind;
        int level = 0;
        if (strcmp(name, "p") == 0) {
            kind = BUNNY_DOC_BLOCK_PARAGRAPH;
        } else if (name[0] == 'h' && name[1] >= '1' && name[1] <= '6' && name[2] == '\0') {
            kind = BUNNY_DOC_BLOCK_HEADING;
            level = name[1] - '0';
        } else if (strcmp(name, "li") == 0) {
            kind = BUNNY_DOC_BLOCK_LIST_ITEM;
        } else {
            /* "ul", "body", or anything else -- not a leaf block itself,
             * just descend past the opening tag and keep scanning for the
             * leaf blocks inside it. */
            pos = close + 1;
            continue;
        }

        size_t inner_open = close + 1;
        size_t inner_close_open = end, inner_close_end = end;
        for (size_t i = inner_open; i < end; i++) {
            if (s[i] != '<') {
                continue;
            }
            size_t c2 = find_close_gt(s, i, end);
            if (c2 == (size_t)-1) {
                continue;
            }
            char n2[8];
            tag_name(s, i, c2, n2, sizeof(n2));
            if (tag_is_closing(s, i) && strcmp(n2, name) == 0) {
                inner_close_open = i;
                inner_close_end = c2 + 1;
                break;
            }
        }

        bunny_doc_block_t block = {.kind = kind, .heading_level = level};
        parse_inline_runs(s, inner_open, inner_close_open, &block.runs);
        if (block.runs.count > 0) {
            if (blocks.count == blocks.cap) {
                blocks.cap = blocks.cap ? blocks.cap * 2 : 8;
                blocks.items = realloc(blocks.items, blocks.cap * sizeof(*blocks.items));
            }
            blocks.items[blocks.count++] = block;
        } else {
            free(block.runs.items);
        }
        pos = inner_close_end;
    }

    out_doc->items = blocks.items;
    out_doc->count = blocks.count;
}

static char *extract_title(const char *s, size_t len)
{
    const char *open_needle = "<title>";
    for (size_t i = 0; i + 7 < len; i++) {
        if (strncmp(s + i, open_needle, 7) == 0) {
            size_t start = i + 7;
            size_t end = start;
            while (end < len && strncmp(s + end, "</title>", 8) != 0) {
                end++;
            }
            return xml_unescape(s, start, end);
        }
    }
    return NULL;
}

bunny_epub_result_t bunny_epub_read(const char *path, bunny_doc_t *out_doc, char **out_title)
{
    if (!path || !out_doc) {
        return BUNNY_EPUB_ERR_INVALID_ARG;
    }
    memset(out_doc, 0, sizeof(*out_doc));
    if (out_title) {
        *out_title = NULL;
    }

    bunny_zip_reader_t *zip = bunny_zip_reader_open(path);
    if (!zip) {
        return BUNNY_EPUB_ERR_IO;
    }

    size_t text_len = 0;
    const unsigned char *text = bunny_zip_reader_get(zip, "OEBPS/text.xhtml", &text_len);
    if (!text) {
        bunny_zip_reader_close(zip);
        return BUNNY_EPUB_ERR_IO;
    }

    const char *body_needle = "<body";
    size_t body_tag_start = (size_t)-1;
    for (size_t i = 0; i + 5 < text_len; i++) {
        if (strncmp((const char *)text + i, body_needle, 5) == 0) {
            body_tag_start = i;
            break;
        }
    }
    if (body_tag_start == (size_t)-1) {
        bunny_zip_reader_close(zip);
        return BUNNY_EPUB_ERR_IO;
    }
    size_t body_open_end = find_close_gt((const char *)text, body_tag_start, text_len);
    if (body_open_end == (size_t)-1) {
        bunny_zip_reader_close(zip);
        return BUNNY_EPUB_ERR_IO;
    }
    size_t body_close_open = text_len;
    for (size_t i = body_open_end + 1; i + 7 <= text_len; i++) {
        if (strncmp((const char *)text + i, "</body>", 7) == 0) {
            body_close_open = i;
            break;
        }
    }

    parse_body_to_doc((const char *)text, body_open_end + 1, body_close_open, out_doc);
    if (out_title) {
        *out_title = extract_title((const char *)text, text_len);
    }

    bunny_zip_reader_close(zip);
    return BUNNY_EPUB_OK;
}
