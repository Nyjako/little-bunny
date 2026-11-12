#include "bunny_common/md5.h"

#include <goblin/hex.h>

void bunny_md5_init(bunny_md5_ctx_t *ctx)
{
    goblin_md5_init(ctx);
}

void bunny_md5_update(bunny_md5_ctx_t *ctx, const void *data, size_t len)
{
    goblin_md5_update(ctx, data, len);
}

void bunny_md5_final(bunny_md5_ctx_t *ctx, char out_hex[33])
{
    unsigned char digest[GOBLIN_MD5_DIGEST_LEN];
    goblin_md5_final(ctx, digest);
    goblin_bytes_to_hex(digest, sizeof(digest), out_hex);
}

void bunny_md5(const void *data, size_t len, char out_hex[33])
{
    bunny_md5_ctx_t ctx;
    bunny_md5_init(&ctx);
    bunny_md5_update(&ctx, data, len);
    bunny_md5_final(&ctx, out_hex);
}
