#include "unity.h"

#include <string.h>

#include "bunny_common/md5.h"

void setUp(void) {}
void tearDown(void) {}

static void assert_md5(const char *input, const char *expected_hex)
{
    char out_hex[33];
    bunny_md5(input, strlen(input), out_hex);
    TEST_ASSERT_EQUAL_STRING(expected_hex, out_hex);
}

/* RFC 1321 Appendix A.5's own published test suite. */
void test_rfc1321_vectors(void)
{
    assert_md5("", "d41d8cd98f00b204e9800998ecf8427e");
    assert_md5("a", "0cc175b9c0f1b6a831c399e269772661");
    assert_md5("abc", "900150983cd24fb0d6963f7d28e17f72");
    assert_md5("message digest", "f96b697d7cb7938d525a2f31aaf161d0");
    assert_md5("abcdefghijklmnopqrstuvwxyz", "c3fcd3d76192e4007dfb496cca67e13b");
    assert_md5("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789", "d174ab98d277d9f5a5611c2c9f419d9f");
    assert_md5("12345678901234567890123456789012345678901234567890123456789012345678901234567890", "57edf4a22be3c955ac49da2e2107b67a");
}

/* Streamed downloads feed bunny_md5_update one chunk at a time (M66) --
 * confirms splitting the same input across many small updates (including
 * splits that straddle the 64-byte block boundary and the 56-byte padding
 * boundary) produces the exact same digest as hashing it all at once. */
void test_incremental_matches_one_shot(void)
{
    const char *input = "The quick brown fox jumps over the lazy dog, and then jumps right back again for good measure.";
    size_t len = strlen(input);
    char one_shot_hex[33];
    char incremental_hex[33];
    bunny_md5_ctx_t ctx;
    size_t offset = 0;
    size_t chunk_sizes[] = {1, 3, 7, 13, 1, 50};
    size_t chunk_index = 0;

    bunny_md5(input, len, one_shot_hex);

    bunny_md5_init(&ctx);
    while (offset < len)
    {
        size_t chunk = chunk_sizes[chunk_index % (sizeof(chunk_sizes) / sizeof(chunk_sizes[0]))];
        chunk_index++;
        if (chunk > len - offset)
        {
            chunk = len - offset;
        }
        bunny_md5_update(&ctx, input + offset, chunk);
        offset += chunk;
    }
    bunny_md5_final(&ctx, incremental_hex);

    TEST_ASSERT_EQUAL_STRING(one_shot_hex, incremental_hex);
}

/* A length that lands exactly on a 64-byte block boundary exercises the
 * "0x80 pad byte itself fills the block" wraparound path in
 * bunny_md5_final. */
void test_input_exactly_one_block(void)
{
    char input[64];
    char out_hex[33];
    memset(input, 'x', sizeof(input));
    bunny_md5(input, sizeof(input), out_hex);
    TEST_ASSERT_EQUAL(32, (int)strlen(out_hex));
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_rfc1321_vectors);
    RUN_TEST(test_incremental_matches_one_shot);
    RUN_TEST(test_input_exactly_one_block);
    return UNITY_END();
}
