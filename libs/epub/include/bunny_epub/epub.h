#ifndef BUNNY_EPUB_H
#define BUNNY_EPUB_H

#include <bunny_common/doc.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum
{
    BUNNY_EPUB_OK = 0,
    BUNNY_EPUB_ERR_INVALID_ARG,
    BUNNY_EPUB_ERR_IO,
} bunny_epub_result_t;

typedef struct
{
    const char *title;                /* required */
    const char *author;               /* may be NULL */
    const unsigned char *cover_image; /* may be NULL -- no cover page is written when absent */
    size_t cover_image_len;
    const char *cover_mimetype; /* e.g. "image/jpeg"; required when cover_image is set */
    const bunny_doc_t *doc;     /* required; the story body */
} bunny_epub_build_params_t;

/*
 * Writes a complete, readable-in-any-e-reader .epub to `dest_path`: the
 * cover image (if supplied) as the book's own cover/first page, the story
 * body rendered from `params->doc` into one styled XHTML page (a small,
 * built-in stylesheet -- serif body text, comfortable line-height/margins,
 * styled headings), plus every other file EPUB's OCF container requires
 * (mimetype, container.xml, content.opf, toc.ncx).
 */
bunny_epub_result_t bunny_epub_build(const bunny_epub_build_params_t *params, const char *dest_path);

/*
 * Reads back an .epub this project's own bunny_epub_build produced --
 * deliberately NOT a general-purpose EPUB reader (an arbitrary third-party
 * .epub's XHTML shape, CSS, or DEFLATE-compressed entries are out of
 * scope). Returns the story body as the same bunny_doc_t shape
 * bunny_bbcode_parse would have produced, plus the book's title
 * (*out_title, caller-owned, free() it) via the OEBPS/text.xhtml page's
 * own <title> text -- out_title may be passed as NULL to skip it.
 */
bunny_epub_result_t bunny_epub_read(const char *path, bunny_doc_t *out_doc, char **out_title);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_EPUB_H */
