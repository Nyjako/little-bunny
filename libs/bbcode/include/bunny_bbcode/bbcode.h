#ifndef BUNNY_BBCODE_H
#define BUNNY_BBCODE_H

#include <bunny_common/doc.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum
{
    BUNNY_BBCODE_OK = 0,
    BUNNY_BBCODE_ERR_INVALID_ARG,
} bunny_bbcode_result_t;

/*
 * Parses Inkbunny's raw story BBCode (the `writing` field, api_submissions.php's
 * own `show_writing` param) into the shared bunny_doc_t model (bunny_common/doc.h).
 *
 * Covers: [b]/[i]/[u] (innermost style wins where they nest -- bunny_doc_run_t
 * has one kind, not a combinable style set, so "[b]bold [i]both[/i][/b]" loses
 * the bold on its italic portion; a deliberate, documented simplification),
 * [url]/[url=...] and bare http(s) URLs, [img]...[/img] (rendered as a URL run
 * pointing at the image URL -- inline images are not fetched/embedded, out of
 * scope for now), [list]/[*] (one BUNNY_DOC_BLOCK_LIST_ITEM block per [*]), and
 * [h1]-[h6] (BUNNY_DOC_BLOCK_HEADING). Plain text outside any block tag is
 * split into BUNNY_DOC_BLOCK_PARAGRAPH blocks on blank lines (two or more
 * consecutive newlines), with a single newline treated as a soft line break
 * (joined with a space) within the same paragraph.
 *
 * Any other/unrecognized tag (e.g. [spoiler], [quote], [size=...]) degrades to
 * plain text -- the tag itself is stripped, its content kept -- rather than
 * showing the raw markup or erroring; this function never fails on malformed
 * input (an unclosed tag is simply treated as open until the end of its
 * block, and a stray/mismatched closing tag is ignored). The only real error
 * is a NULL/invalid argument.
 */
bunny_bbcode_result_t bunny_bbcode_parse(const char *bbcode, bunny_doc_t *out_doc);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_BBCODE_H */
