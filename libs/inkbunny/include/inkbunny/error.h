#ifndef INKBUNNY_ERROR_H
#define INKBUNNY_ERROR_H

#ifdef __cplusplus
extern "C" {
#endif

typedef enum
{
    INKBUNNY_OK = 0,
    INKBUNNY_ERR_INVALID_ARG,
    INKBUNNY_ERR_NETWORK,
    INKBUNNY_ERR_AUTH,
    INKBUNNY_ERR_NOT_FOUND,
    INKBUNNY_ERR_RATE_LIMITED,
    INKBUNNY_ERR_PARSE,
    INKBUNNY_ERR_SERVER,
    INKBUNNY_ERR_UNKNOWN,
} inkbunny_result_t;

const char *inkbunny_result_to_string(inkbunny_result_t result);

#ifdef __cplusplus
}
#endif

#endif /* INKBUNNY_ERROR_H */
