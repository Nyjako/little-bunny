#ifndef BUNNY_COMMON_DOC_H
#define BUNNY_COMMON_DOC_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * A small, site/format-agnostic rich-text document model -- the shared
 * shape both `libs/bbcode` (parses Inkbunny's raw `writing` BBCode into
 * this) and `libs/epub` (renders this to/from an .epub's XHTML) produce
 * and consume, so every reader on the Dart side works off one JSON shape
 * regardless of whether the content was just parsed live or read back from
 * a previously-downloaded .epub. Deliberately small: only the handful of
 * constructs Inkbunny's story BBCode actually uses (plain/bold/italic/
 * underline/link runs inside a paragraph/heading/list-item block) -- not a
 * general-purpose rich-text or HTML model.
 */
typedef enum
{
    BUNNY_DOC_BLOCK_PARAGRAPH,
    BUNNY_DOC_BLOCK_HEADING,
    BUNNY_DOC_BLOCK_LIST_ITEM,
} bunny_doc_block_kind_t;

typedef enum
{
    BUNNY_DOC_RUN_PLAIN,
    BUNNY_DOC_RUN_BOLD,
    BUNNY_DOC_RUN_ITALIC,
    BUNNY_DOC_RUN_UNDERLINE,
    BUNNY_DOC_RUN_URL,
} bunny_doc_run_kind_t;

typedef struct
{
    bunny_doc_run_kind_t kind;
    char *text; /* always set -- the run's visible text */
    char *url;  /* only set (non-NULL) for BUNNY_DOC_RUN_URL */
} bunny_doc_run_t;

typedef struct
{
    bunny_doc_run_t *items;
    size_t count;
} bunny_doc_run_list_t;

typedef struct
{
    bunny_doc_block_kind_t kind;
    int heading_level; /* 1-6; only meaningful when kind == BUNNY_DOC_BLOCK_HEADING */
    bunny_doc_run_list_t runs;
} bunny_doc_block_t;

typedef struct
{
    bunny_doc_block_t *items;
    size_t count;
} bunny_doc_t;

/* Frees every block/run and their owned strings, then zeroes *doc. Safe to
 * call on an already-zeroed (memset(0)) bunny_doc_t, and safe on NULL. */
void bunny_doc_free(bunny_doc_t *doc);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_COMMON_DOC_H */
