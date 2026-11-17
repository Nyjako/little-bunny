#include "zip.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- CRC-32 (reflected, polynomial 0xEDB88320 -- the standard ZIP/PNG/
 * gzip variant) -- small and self-contained, no vendored dependency. ---- */

static uint32_t crc32_table[256];
static bool crc32_table_ready = false;

static void crc32_init_table(void)
{
    if (crc32_table_ready) {
        return;
    }
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int k = 0; k < 8; k++) {
            c = (c & 1) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
        }
        crc32_table[i] = c;
    }
    crc32_table_ready = true;
}

static uint32_t crc32_compute(const unsigned char *data, size_t len)
{
    crc32_init_table();
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < len; i++) {
        c = crc32_table[(c ^ data[i]) & 0xFF] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFFu;
}

/* ---- little-endian field helpers ---- */

static void put_u16(unsigned char *p, uint16_t v)
{
    p[0] = (unsigned char)(v & 0xFF);
    p[1] = (unsigned char)((v >> 8) & 0xFF);
}

static void put_u32(unsigned char *p, uint32_t v)
{
    p[0] = (unsigned char)(v & 0xFF);
    p[1] = (unsigned char)((v >> 8) & 0xFF);
    p[2] = (unsigned char)((v >> 16) & 0xFF);
    p[3] = (unsigned char)((v >> 24) & 0xFF);
}

static uint16_t get_u16(const unsigned char *p)
{
    return (uint16_t)(p[0] | (p[1] << 8));
}

static uint32_t get_u32(const unsigned char *p)
{
    return (uint32_t)(p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24));
}

/* A fixed, valid-but-meaningless DOS date/time (1980-01-01 00:00:00) --
 * every reader accepts it, and an EPUB's own modification time has no
 * reader-visible meaning worth tracking accurately. */
#define BUNNY_ZIP_DOS_TIME 0u
#define BUNNY_ZIP_DOS_DATE 0x21u

/* ---- writer ---- */

typedef struct
{
    char *name;
    uint32_t crc;
    uint32_t size;
    uint32_t offset; /* where this entry's local header starts */
} bunny_zip_writer_entry_t;

struct bunny_zip_writer
{
    FILE *f;
    bool ok;
    bunny_zip_writer_entry_t *entries;
    size_t count;
    size_t cap;
};

bunny_zip_writer_t *bunny_zip_writer_open(const char *path)
{
    FILE *f = fopen(path, "wb");
    if (!f) {
        return NULL;
    }
    bunny_zip_writer_t *zip = calloc(1, sizeof(*zip));
    if (!zip) {
        fclose(f);
        return NULL;
    }
    zip->f = f;
    zip->ok = true;
    return zip;
}

bool bunny_zip_writer_add(bunny_zip_writer_t *zip, const char *name, const unsigned char *data, size_t len)
{
    if (!zip || !zip->ok) {
        return false;
    }

    long offset_long = ftell(zip->f);
    if (offset_long < 0) {
        zip->ok = false;
        return false;
    }
    uint32_t offset = (uint32_t)offset_long;
    uint32_t crc = crc32_compute(data, len);
    uint16_t name_len = (uint16_t)strlen(name);

    unsigned char header[30];
    put_u32(header + 0, 0x04034b50u);
    put_u16(header + 4, 20); /* version needed to extract */
    put_u16(header + 6, 0);  /* general purpose bit flag */
    put_u16(header + 8, 0);  /* compression method: stored */
    put_u16(header + 10, BUNNY_ZIP_DOS_TIME);
    put_u16(header + 12, BUNNY_ZIP_DOS_DATE);
    put_u32(header + 14, crc);
    put_u32(header + 18, (uint32_t)len);
    put_u32(header + 22, (uint32_t)len);
    put_u16(header + 26, name_len);
    put_u16(header + 28, 0); /* extra field length */

    if (fwrite(header, 1, sizeof(header), zip->f) != sizeof(header) || fwrite(name, 1, name_len, zip->f) != name_len || (len > 0 && fwrite(data, 1, len, zip->f) != len)) {
        zip->ok = false;
        return false;
    }

    if (zip->count == zip->cap) {
        size_t new_cap = zip->cap ? zip->cap * 2 : 8;
        bunny_zip_writer_entry_t *grown = realloc(zip->entries, new_cap * sizeof(*grown));
        if (!grown) {
            zip->ok = false;
            return false;
        }
        zip->entries = grown;
        zip->cap = new_cap;
    }
    char *name_copy = malloc(name_len + 1);
    if (!name_copy) {
        zip->ok = false;
        return false;
    }
    memcpy(name_copy, name, name_len + 1);
    zip->entries[zip->count].name = name_copy;
    zip->entries[zip->count].crc = crc;
    zip->entries[zip->count].size = (uint32_t)len;
    zip->entries[zip->count].offset = offset;
    zip->count++;
    return true;
}

bool bunny_zip_writer_close(bunny_zip_writer_t *zip)
{
    if (!zip) {
        return false;
    }
    bool ok = zip->ok;

    if (ok) {
        long cd_start_long = ftell(zip->f);
        if (cd_start_long < 0) {
            ok = false;
        } else {
            uint32_t cd_start = (uint32_t)cd_start_long;
            for (size_t i = 0; ok && i < zip->count; i++) {
                bunny_zip_writer_entry_t *e = &zip->entries[i];
                uint16_t name_len = (uint16_t)strlen(e->name);
                unsigned char record[46];
                put_u32(record + 0, 0x02014b50u);
                put_u16(record + 4, 20); /* version made by */
                put_u16(record + 6, 20); /* version needed to extract */
                put_u16(record + 8, 0);  /* general purpose bit flag */
                put_u16(record + 10, 0); /* compression method: stored */
                put_u16(record + 12, BUNNY_ZIP_DOS_TIME);
                put_u16(record + 14, BUNNY_ZIP_DOS_DATE);
                put_u32(record + 16, e->crc);
                put_u32(record + 20, e->size);
                put_u32(record + 24, e->size);
                put_u16(record + 28, name_len);
                put_u16(record + 30, 0); /* extra field length */
                put_u16(record + 32, 0); /* file comment length */
                put_u16(record + 34, 0); /* disk number start */
                put_u16(record + 36, 0); /* internal file attributes */
                put_u32(record + 38, 0); /* external file attributes */
                put_u32(record + 42, e->offset);
                if (fwrite(record, 1, sizeof(record), zip->f) != sizeof(record) || fwrite(e->name, 1, name_len, zip->f) != name_len) {
                    ok = false;
                }
            }

            if (ok) {
                long cd_end_long = ftell(zip->f);
                if (cd_end_long < 0) {
                    ok = false;
                } else {
                    uint32_t cd_size = (uint32_t)(cd_end_long - (long)cd_start);
                    unsigned char eocd[22];
                    put_u32(eocd + 0, 0x06054b50u);
                    put_u16(eocd + 4, 0); /* number of this disk */
                    put_u16(eocd + 6, 0); /* disk where central directory starts */
                    put_u16(eocd + 8, (uint16_t)zip->count);
                    put_u16(eocd + 10, (uint16_t)zip->count);
                    put_u32(eocd + 12, cd_size);
                    put_u32(eocd + 16, cd_start);
                    put_u16(eocd + 20, 0); /* comment length */
                    if (fwrite(eocd, 1, sizeof(eocd), zip->f) != sizeof(eocd)) {
                        ok = false;
                    }
                }
            }
        }
    }

    if (fclose(zip->f) != 0) {
        ok = false;
    }
    for (size_t i = 0; i < zip->count; i++) {
        free(zip->entries[i].name);
    }
    free(zip->entries);
    free(zip);
    return ok;
}

/* ---- reader ---- */

typedef struct
{
    char *name;
    uint32_t offset; /* local header offset */
    uint32_t size;
    uint16_t method;
} bunny_zip_reader_entry_t;

struct bunny_zip_reader
{
    unsigned char *buf;
    size_t buf_len;
    bunny_zip_reader_entry_t *entries;
    size_t count;
};

static long file_size(FILE *f)
{
    if (fseek(f, 0, SEEK_END) != 0) {
        return -1;
    }
    long size = ftell(f);
    if (size < 0 || fseek(f, 0, SEEK_SET) != 0) {
        return -1;
    }
    return size;
}

bunny_zip_reader_t *bunny_zip_reader_open(const char *path)
{
    FILE *f = fopen(path, "rb");
    if (!f) {
        return NULL;
    }
    long size = file_size(f);
    if (size < 22) {
        fclose(f);
        return NULL;
    }
    unsigned char *buf = malloc((size_t)size);
    if (!buf) {
        fclose(f);
        return NULL;
    }
    size_t read = fread(buf, 1, (size_t)size, f);
    fclose(f);
    if (read != (size_t)size) {
        free(buf);
        return NULL;
    }

    /* This reader only ever opens files this project's own writer
     * produced, which never append a zip comment -- the end-of-central-
     * directory record is therefore always exactly the last 22 bytes. */
    const unsigned char *eocd = buf + (size_t)size - 22;
    if (get_u32(eocd) != 0x06054b50u) {
        free(buf);
        return NULL;
    }
    uint16_t entry_count = get_u16(eocd + 10);
    uint32_t cd_offset = get_u32(eocd + 16);
    if (cd_offset >= (size_t)size) {
        free(buf);
        return NULL;
    }

    bunny_zip_reader_entry_t *entries = calloc(entry_count ? entry_count : 1, sizeof(*entries));
    if (!entries) {
        free(buf);
        return NULL;
    }

    size_t pos = cd_offset;
    size_t parsed = 0;
    for (; parsed < entry_count; parsed++) {
        if (pos + 46 > (size_t)size || get_u32(buf + pos) != 0x02014b50u) {
            break;
        }
        uint16_t method = get_u16(buf + pos + 10);
        uint32_t uncompressed_size = get_u32(buf + pos + 24);
        uint16_t name_len = get_u16(buf + pos + 28);
        uint16_t extra_len = get_u16(buf + pos + 30);
        uint16_t comment_len = get_u16(buf + pos + 32);
        uint32_t local_offset = get_u32(buf + pos + 42);
        if (pos + 46 + name_len > (size_t)size) {
            break;
        }
        char *name = malloc((size_t)name_len + 1);
        if (!name) {
            break;
        }
        memcpy(name, buf + pos + 46, name_len);
        name[name_len] = '\0';
        entries[parsed].name = name;
        entries[parsed].offset = local_offset;
        entries[parsed].size = uncompressed_size;
        entries[parsed].method = method;
        pos += 46 + name_len + extra_len + comment_len;
    }

    bunny_zip_reader_t *zip = calloc(1, sizeof(*zip));
    if (!zip) {
        for (size_t i = 0; i < parsed; i++) {
            free(entries[i].name);
        }
        free(entries);
        free(buf);
        return NULL;
    }
    zip->buf = buf;
    zip->buf_len = (size_t)size;
    zip->entries = entries;
    zip->count = parsed;
    return zip;
}

const unsigned char *bunny_zip_reader_get(bunny_zip_reader_t *zip, const char *name, size_t *out_len)
{
    if (!zip || !name || !out_len) {
        return NULL;
    }
    for (size_t i = 0; i < zip->count; i++) {
        if (strcmp(zip->entries[i].name, name) != 0) {
            continue;
        }
        bunny_zip_reader_entry_t *e = &zip->entries[i];
        if (e->method != 0) {
            return NULL; /* this reader only understands stored entries */
        }
        if (e->offset + 30 > zip->buf_len) {
            return NULL;
        }
        uint16_t local_name_len = get_u16(zip->buf + e->offset + 26);
        uint16_t local_extra_len = get_u16(zip->buf + e->offset + 28);
        size_t data_offset = (size_t)e->offset + 30 + local_name_len + local_extra_len;
        if (data_offset + e->size > zip->buf_len) {
            return NULL;
        }
        *out_len = e->size;
        return zip->buf + data_offset;
    }
    return NULL;
}

void bunny_zip_reader_close(bunny_zip_reader_t *zip)
{
    if (!zip) {
        return;
    }
    for (size_t i = 0; i < zip->count; i++) {
        free(zip->entries[i].name);
    }
    free(zip->entries);
    free(zip->buf);
    free(zip);
}
