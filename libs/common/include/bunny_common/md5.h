#ifndef BUNNY_COMMON_MD5_H
#define BUNNY_COMMON_MD5_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * A small, self-contained MD5 implementation (RFC 1321) -- used only to
 * verify a downloaded file's bytes against a site-published checksum
 * (e621/Inkbunny's own `file_md5`), never as a security boundary, so MD5's
 * well-known collision weaknesses are irrelevant here. No system/TLS-backend
 * MD5 is reliably available to link against from every target this project
 * ships for (OpenSSL is only linked server-side, Android has no prebuilt
 * OpenSSL at all -- see CMakeLists.txt), hence vendoring this instead.
 *
 * Incremental (init/update/final) so a streamed download can be hashed as
 * each chunk arrives, without buffering the whole file a second time just
 * to hash it afterward.
 */
typedef struct
{
    uint32_t state[4];
    uint64_t total_len; /* total bytes fed to bunny_md5_update so far */
    unsigned char buffer[64];
    size_t buffer_len; /* bytes currently sitting in buffer, always < 64 */
} bunny_md5_ctx_t;

void bunny_md5_init(bunny_md5_ctx_t *ctx);
void bunny_md5_update(bunny_md5_ctx_t *ctx, const void *data, size_t len);

/* Writes 32 lowercase hex characters plus a NUL terminator into out_hex
 * (must be at least 33 bytes). ctx is consumed -- call bunny_md5_init again
 * before reusing it. */
void bunny_md5_final(bunny_md5_ctx_t *ctx, char out_hex[33]);

/* One-shot convenience wrapper around init/update/final, for callers that
 * already have the whole buffer in memory. */
void bunny_md5(const void *data, size_t len, char out_hex[33]);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_COMMON_MD5_H */
