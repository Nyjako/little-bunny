#include "bunny_common/doc.h"

#include <stdlib.h>
#include <string.h>

static void free_run(bunny_doc_run_t *run)
{
    free(run->text);
    free(run->url);
}

void bunny_doc_free(bunny_doc_t *doc)
{
    if (!doc) {
        return;
    }
    for (size_t i = 0; i < doc->count; i++) {
        bunny_doc_block_t *block = &doc->items[i];
        for (size_t j = 0; j < block->runs.count; j++) {
            free_run(&block->runs.items[j]);
        }
        free(block->runs.items);
    }
    free(doc->items);
    memset(doc, 0, sizeof(*doc));
}
