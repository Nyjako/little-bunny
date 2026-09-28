#ifndef BUNNY_CORE_ERROR_H
#define BUNNY_CORE_ERROR_H

#ifdef __cplusplus
extern "C" {
#endif

typedef enum
{
    BUNNY_CORE_OK = 0,
    BUNNY_CORE_ERR_INVALID_ARG,
    BUNNY_CORE_ERR_NOT_FOUND,
    BUNNY_CORE_ERR_DB,
    BUNNY_CORE_ERR_SITE, /* an e621/Inkbunny client call failed (network, auth, ...) */
    BUNNY_CORE_ERR_UNKNOWN,
} bunny_core_result_t;

const char *bunny_core_result_to_string(bunny_core_result_t result);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_CORE_ERROR_H */
