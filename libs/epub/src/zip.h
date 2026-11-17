#ifndef BUNNY_EPUB_ZIP_H
#define BUNNY_EPUB_ZIP_H

#include <stdbool.h>
#include <stddef.h>

/*
 * A minimal, STORE-only (uncompressed) ZIP reader/writer -- everything
 * EPUB's own OCF container needs and nothing more: a flat list of named
 * entries, no directories-as-entries, no DEFLATE, no encryption, no
 * multi-disk/spanned archives, no zip comment. Internal to libs/epub, not
 * a general-purpose zip library.
 *
 * Writing uncompressed is deliberate (see libs/epub's own top-level doc
 * comment): EPUB's spec already requires the `mimetype` entry to be stored
 * uncompressed anyway, and a story's text is small enough that skipping
 * DEFLATE costs nothing that matters, in exchange for not vendoring a
 * compression library.
 */

typedef struct bunny_zip_writer bunny_zip_writer_t;

/* NULL if `path` can't be opened for writing. */
bunny_zip_writer_t *bunny_zip_writer_open(const char *path);

/* Appends one stored entry. `name` is the entry's path inside the archive
 * (e.g. "META-INF/container.xml"), always written with '/' separators.
 * Returns false on an I/O failure -- the writer is left open but unusable;
 * bunny_zip_writer_close will also report failure in that case. */
bool bunny_zip_writer_add(bunny_zip_writer_t *zip, const char *name, const unsigned char *data, size_t len);

/* Writes the central directory + end-of-central-directory record and
 * closes the underlying file, then frees `zip` regardless of outcome.
 * Returns false if this or any earlier bunny_zip_writer_add call failed. */
bool bunny_zip_writer_close(bunny_zip_writer_t *zip);

typedef struct bunny_zip_reader bunny_zip_reader_t;

/* Reads the whole file into memory and parses its central directory. NULL
 * on any failure (not found, truncated, no valid end-of-central-directory
 * record). Scoped to ZIPs this project's own writer produced. */
bunny_zip_reader_t *bunny_zip_reader_open(const char *path);

/* Looks up `name` (exact match) and returns a pointer into the reader's
 * own in-memory buffer (valid only until bunny_zip_reader_close -- copy it
 * if the caller needs it to outlive the reader) plus its length via
 * *out_len. NULL if `name` isn't present, or is present but wasn't stored
 * with method 0 (uncompressed) -- this reader never decompresses. */
const unsigned char *bunny_zip_reader_get(bunny_zip_reader_t *zip, const char *name, size_t *out_len);

void bunny_zip_reader_close(bunny_zip_reader_t *zip);

#endif /* BUNNY_EPUB_ZIP_H */
