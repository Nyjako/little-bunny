#include "bunny_common/md5.h"

#include <string.h>

/* Standard RFC 1321 per-round auxiliary functions/shifts/step macros --
 * identical in every MD5 implementation, since they're the algorithm
 * itself, not an expression of anyone's particular style. */
#define BUNNY_MD5_F(x, y, z) (((x) & (y)) | (~(x) & (z)))
#define BUNNY_MD5_G(x, y, z) (((x) & (z)) | ((y) & ~(z)))
#define BUNNY_MD5_H(x, y, z) ((x) ^ (y) ^ (z))
#define BUNNY_MD5_I(x, y, z) ((y) ^ ((x) | ~(z)))

#define BUNNY_MD5_ROTL(x, n) (((x) << (n)) | ((x) >> (32 - (n))))

#define BUNNY_MD5_FF(a, b, c, d, x, s, ac)                        \
    {                                                             \
        (a) += BUNNY_MD5_F((b), (c), (d)) + (x) + (uint32_t)(ac); \
        (a) = BUNNY_MD5_ROTL((a), (s));                           \
        (a) += (b);                                               \
    }
#define BUNNY_MD5_GG(a, b, c, d, x, s, ac)                        \
    {                                                             \
        (a) += BUNNY_MD5_G((b), (c), (d)) + (x) + (uint32_t)(ac); \
        (a) = BUNNY_MD5_ROTL((a), (s));                           \
        (a) += (b);                                               \
    }
#define BUNNY_MD5_HH(a, b, c, d, x, s, ac)                        \
    {                                                             \
        (a) += BUNNY_MD5_H((b), (c), (d)) + (x) + (uint32_t)(ac); \
        (a) = BUNNY_MD5_ROTL((a), (s));                           \
        (a) += (b);                                               \
    }
#define BUNNY_MD5_II(a, b, c, d, x, s, ac)                        \
    {                                                             \
        (a) += BUNNY_MD5_I((b), (c), (d)) + (x) + (uint32_t)(ac); \
        (a) = BUNNY_MD5_ROTL((a), (s));                           \
        (a) += (b);                                               \
    }

/* Processes exactly one 64-byte block, folding it into state. */
static void bunny_md5_transform(uint32_t state[4], const unsigned char block[64])
{
    uint32_t a = state[0], b = state[1], c = state[2], d = state[3];
    uint32_t x[16];
    int i;

    for (i = 0; i < 16; i++) {
        x[i] = (uint32_t)block[i * 4] | ((uint32_t)block[i * 4 + 1] << 8) | ((uint32_t)block[i * 4 + 2] << 16) | ((uint32_t)block[i * 4 + 3] << 24);
    }

    BUNNY_MD5_FF(a, b, c, d, x[0], 7, 0xd76aa478);
    BUNNY_MD5_FF(d, a, b, c, x[1], 12, 0xe8c7b756);
    BUNNY_MD5_FF(c, d, a, b, x[2], 17, 0x242070db);
    BUNNY_MD5_FF(b, c, d, a, x[3], 22, 0xc1bdceee);
    BUNNY_MD5_FF(a, b, c, d, x[4], 7, 0xf57c0faf);
    BUNNY_MD5_FF(d, a, b, c, x[5], 12, 0x4787c62a);
    BUNNY_MD5_FF(c, d, a, b, x[6], 17, 0xa8304613);
    BUNNY_MD5_FF(b, c, d, a, x[7], 22, 0xfd469501);
    BUNNY_MD5_FF(a, b, c, d, x[8], 7, 0x698098d8);
    BUNNY_MD5_FF(d, a, b, c, x[9], 12, 0x8b44f7af);
    BUNNY_MD5_FF(c, d, a, b, x[10], 17, 0xffff5bb1);
    BUNNY_MD5_FF(b, c, d, a, x[11], 22, 0x895cd7be);
    BUNNY_MD5_FF(a, b, c, d, x[12], 7, 0x6b901122);
    BUNNY_MD5_FF(d, a, b, c, x[13], 12, 0xfd987193);
    BUNNY_MD5_FF(c, d, a, b, x[14], 17, 0xa679438e);
    BUNNY_MD5_FF(b, c, d, a, x[15], 22, 0x49b40821);

    BUNNY_MD5_GG(a, b, c, d, x[1], 5, 0xf61e2562);
    BUNNY_MD5_GG(d, a, b, c, x[6], 9, 0xc040b340);
    BUNNY_MD5_GG(c, d, a, b, x[11], 14, 0x265e5a51);
    BUNNY_MD5_GG(b, c, d, a, x[0], 20, 0xe9b6c7aa);
    BUNNY_MD5_GG(a, b, c, d, x[5], 5, 0xd62f105d);
    BUNNY_MD5_GG(d, a, b, c, x[10], 9, 0x02441453);
    BUNNY_MD5_GG(c, d, a, b, x[15], 14, 0xd8a1e681);
    BUNNY_MD5_GG(b, c, d, a, x[4], 20, 0xe7d3fbc8);
    BUNNY_MD5_GG(a, b, c, d, x[9], 5, 0x21e1cde6);
    BUNNY_MD5_GG(d, a, b, c, x[14], 9, 0xc33707d6);
    BUNNY_MD5_GG(c, d, a, b, x[3], 14, 0xf4d50d87);
    BUNNY_MD5_GG(b, c, d, a, x[8], 20, 0x455a14ed);
    BUNNY_MD5_GG(a, b, c, d, x[13], 5, 0xa9e3e905);
    BUNNY_MD5_GG(d, a, b, c, x[2], 9, 0xfcefa3f8);
    BUNNY_MD5_GG(c, d, a, b, x[7], 14, 0x676f02d9);
    BUNNY_MD5_GG(b, c, d, a, x[12], 20, 0x8d2a4c8a);

    BUNNY_MD5_HH(a, b, c, d, x[5], 4, 0xfffa3942);
    BUNNY_MD5_HH(d, a, b, c, x[8], 11, 0x8771f681);
    BUNNY_MD5_HH(c, d, a, b, x[11], 16, 0x6d9d6122);
    BUNNY_MD5_HH(b, c, d, a, x[14], 23, 0xfde5380c);
    BUNNY_MD5_HH(a, b, c, d, x[1], 4, 0xa4beea44);
    BUNNY_MD5_HH(d, a, b, c, x[4], 11, 0x4bdecfa9);
    BUNNY_MD5_HH(c, d, a, b, x[7], 16, 0xf6bb4b60);
    BUNNY_MD5_HH(b, c, d, a, x[10], 23, 0xbebfbc70);
    BUNNY_MD5_HH(a, b, c, d, x[13], 4, 0x289b7ec6);
    BUNNY_MD5_HH(d, a, b, c, x[0], 11, 0xeaa127fa);
    BUNNY_MD5_HH(c, d, a, b, x[3], 16, 0xd4ef3085);
    BUNNY_MD5_HH(b, c, d, a, x[6], 23, 0x04881d05);
    BUNNY_MD5_HH(a, b, c, d, x[9], 4, 0xd9d4d039);
    BUNNY_MD5_HH(d, a, b, c, x[12], 11, 0xe6db99e5);
    BUNNY_MD5_HH(c, d, a, b, x[15], 16, 0x1fa27cf8);
    BUNNY_MD5_HH(b, c, d, a, x[2], 23, 0xc4ac5665);

    BUNNY_MD5_II(a, b, c, d, x[0], 6, 0xf4292244);
    BUNNY_MD5_II(d, a, b, c, x[7], 10, 0x432aff97);
    BUNNY_MD5_II(c, d, a, b, x[14], 15, 0xab9423a7);
    BUNNY_MD5_II(b, c, d, a, x[5], 21, 0xfc93a039);
    BUNNY_MD5_II(a, b, c, d, x[12], 6, 0x655b59c3);
    BUNNY_MD5_II(d, a, b, c, x[3], 10, 0x8f0ccc92);
    BUNNY_MD5_II(c, d, a, b, x[10], 15, 0xffeff47d);
    BUNNY_MD5_II(b, c, d, a, x[1], 21, 0x85845dd1);
    BUNNY_MD5_II(a, b, c, d, x[8], 6, 0x6fa87e4f);
    BUNNY_MD5_II(d, a, b, c, x[15], 10, 0xfe2ce6e0);
    BUNNY_MD5_II(c, d, a, b, x[6], 15, 0xa3014314);
    BUNNY_MD5_II(b, c, d, a, x[13], 21, 0x4e0811a1);
    BUNNY_MD5_II(a, b, c, d, x[4], 6, 0xf7537e82);
    BUNNY_MD5_II(d, a, b, c, x[11], 10, 0xbd3af235);
    BUNNY_MD5_II(c, d, a, b, x[2], 15, 0x2ad7d2bb);
    BUNNY_MD5_II(b, c, d, a, x[9], 21, 0xeb86d391);

    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
}

void bunny_md5_init(bunny_md5_ctx_t *ctx)
{
    ctx->state[0] = 0x67452301;
    ctx->state[1] = 0xefcdab89;
    ctx->state[2] = 0x98badcfe;
    ctx->state[3] = 0x10325476;
    ctx->total_len = 0;
    ctx->buffer_len = 0;
}

void bunny_md5_update(bunny_md5_ctx_t *ctx, const void *data, size_t len)
{
    const unsigned char *p = (const unsigned char *)data;
    ctx->total_len += len;

    while (len > 0) {
        size_t take = 64 - ctx->buffer_len;
        if (take > len) {
            take = len;
        }
        memcpy(ctx->buffer + ctx->buffer_len, p, take);
        ctx->buffer_len += take;
        p += take;
        len -= take;

        if (ctx->buffer_len == 64) {
            bunny_md5_transform(ctx->state, ctx->buffer);
            ctx->buffer_len = 0;
        }
    }
}

void bunny_md5_final(bunny_md5_ctx_t *ctx, char out_hex[33])
{
    static const char hex_digits[] = "0123456789abcdef";
    uint64_t bit_len = ctx->total_len * 8; /* captured before further updates below grow total_len */
    unsigned char pad_byte = 0x80;
    unsigned char zero_byte = 0;
    unsigned char length_bytes[8];
    size_t i;

    bunny_md5_update(ctx, &pad_byte, 1);
    /* Pad with zeros until exactly 8 bytes (the length field below) are left
     * in this block -- bunny_md5_update's own 64-byte flush logic already
     * handles wrapping into a fresh block if the 0x80 byte above left less
     * than 8 bytes of room. */
    while (ctx->buffer_len != 56) {
        bunny_md5_update(ctx, &zero_byte, 1);
    }

    for (i = 0; i < 8; i++) {
        length_bytes[i] = (unsigned char)(bit_len >> (8 * i));
    }
    bunny_md5_update(ctx, length_bytes, 8);

    for (i = 0; i < 4; i++) {
        uint32_t word = ctx->state[i];
        size_t byte_index;
        for (byte_index = 0; byte_index < 4; byte_index++) {
            unsigned char byte_value = (unsigned char)(word >> (8 * byte_index));
            out_hex[(i * 4 + byte_index) * 2] = hex_digits[(byte_value >> 4) & 0xf];
            out_hex[(i * 4 + byte_index) * 2 + 1] = hex_digits[byte_value & 0xf];
        }
    }
    out_hex[32] = '\0';
}

void bunny_md5(const void *data, size_t len, char out_hex[33])
{
    bunny_md5_ctx_t ctx;
    bunny_md5_init(&ctx);
    bunny_md5_update(&ctx, data, len);
    bunny_md5_final(&ctx, out_hex);
}
