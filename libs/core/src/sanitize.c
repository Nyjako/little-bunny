#include "bunny_core/core.h"

#include <string.h>

size_t bunny_filename_max_len(void)
{
    return BUNNY_FILENAME_MAX_LEN;
}

static bool is_windows_reserved(unsigned char c)
{
    switch (c) {
        case '<':
        case '>':
        case ':':
        case '"':
        case '/':
        case '\\':
        case '|':
        case '?':
        case '*':
            return true;
        default:
            return false;
    }
}

static bool is_allowed_ascii_byte(unsigned char c)
{
    if (c < 0x20 || c == 0x7F) {
        return false;
    }
    return !is_windows_reserved(c);
}

static bool is_utf8_continuation_byte(unsigned char c)
{
    return (c & 0xC0) == 0x80;
}

size_t bunny_sanitize_filename_segment(const char *input, bool ascii_only, char *out_buf, size_t out_buf_size)
{
    if (!out_buf || out_buf_size == 0) {
        return 0;
    }
    if (!input) {
        input = "";
    }

    size_t input_len = strlen(input);
    size_t out_len = 0;
    size_t i = 0;

    while (i < input_len) {
        unsigned char c = (unsigned char)input[i];

        if (c < 0x80) {
            if (out_len + 1 >= out_buf_size) {
                break;
            }
            out_buf[out_len++] = is_allowed_ascii_byte(c) ? (char)c : '_';
            i++;
            continue;
        }

        /* c >= 0x80: the first byte of a (possibly multi-byte) UTF-8
         * sequence. */
        size_t seq_len = 1;
        while (i + seq_len < input_len && is_utf8_continuation_byte((unsigned char)input[i + seq_len])) {
            seq_len++;
        }

        if (ascii_only) {
            if (out_len + 1 >= out_buf_size) {
                break;
            }
            out_buf[out_len++] = '_';
            i += seq_len;
            continue;
        }

        if (out_len + seq_len + 1 > out_buf_size) {
            /* The whole sequence doesn't fit -- stop rather than split it. */
            break;
        }
        memcpy(out_buf + out_len, input + i, seq_len);
        out_len += seq_len;
        i += seq_len;
    }

    /* Windows can't create a name ending in '.' or ' ' -- both are
     * single-byte ASCII, safe to trim regardless of ascii_only. */
    while (out_len > 0 && (out_buf[out_len - 1] == '.' || out_buf[out_len - 1] == ' ')) {
        out_len--;
    }

    if (out_len == 0 && out_buf_size >= 2) {
        out_buf[0] = '_';
        out_len = 1;
    }
    out_buf[out_len] = '\0';
    return out_len;
}
