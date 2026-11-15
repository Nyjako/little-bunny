#include "bunny_core/core.h"

#include <goblin/ascii_transliterate.h>
#include <goblin/sanitize_filename.h>

#include <stdlib.h>
#include <string.h>

size_t bunny_filename_max_len(void)
{
    return BUNNY_FILENAME_MAX_LEN;
}

/* Thin wrapper over GOBLIN's own sanitize_filename.h -- bunny_core used to
 * hand-roll this (naive continuation-byte counting, no reserved-device-name
 * handling), now upstreamed into GOBLIN with proper UTF-8 validation and a
 * Windows reserved-name check, so this just delegates. The one addition
 * here: when ascii_only is true, this transliterates known Latin diacritics
 * to their plain-ASCII base letter first (e.g. "e" for a pool title, not a
 * lossy "_") -- composing GOBLIN's two headers exactly as their own doc
 * comments recommend, rather than relying on sanitize_filename's own
 * ascii_only collapse-to-'_' for text that has a better ASCII equivalent.
 * Not applied when ascii_only is false -- goblin_transliterate_to_ascii
 * replaces EVERY non-Latin codepoint with a fallback byte too, which would
 * defeat the point of asking to keep non-ASCII text verbatim. */
size_t bunny_sanitize_filename_segment(const char *input, bool ascii_only, char *out_buf, size_t out_buf_size)
{
    if (!ascii_only || !input) {
        return goblin_sanitize_filename_segment(input, ascii_only, out_buf, out_buf_size);
    }

    /* Transliteration never produces more bytes than the input it reads
     * (every multi-byte table entry is at most 2 ASCII bytes for a source
     * codepoint that was itself at least 2 bytes; anything else collapses
     * to exactly 1 byte) -- strlen(input) + 1 is always enough. Falls back
     * to sanitizing the original input directly (diacritics collapse to
     * '_' instead of folding) if the allocation fails, rather than
     * crashing over what is, worst case, a slightly lower-quality result. */
    size_t cap = strlen(input) + 1;
    char *transliterated = malloc(cap);
    if (!transliterated) {
        return goblin_sanitize_filename_segment(input, true, out_buf, out_buf_size);
    }
    goblin_transliterate_to_ascii(input, '_', transliterated, cap);
    size_t result = goblin_sanitize_filename_segment(transliterated, true, out_buf, out_buf_size);
    free(transliterated);
    return result;
}
