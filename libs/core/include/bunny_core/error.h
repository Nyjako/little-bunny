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
    /* The site call itself succeeded, but what it returned can't be shown in
     * this app (M28) -- e.g. an Inkbunny submission whose primary file is
     * Shockwave/Flash (application/x-shockwave-flash), which has no runtime
     * here and no preview/thumbnail the API can fall back to. Distinct from
     * BUNNY_CORE_ERR_SITE so logs/callers can tell "the network/site call
     * failed" apart from "it worked, but this is deliberately unsupported." */
    BUNNY_CORE_ERR_UNSUPPORTED_FORMAT,
    BUNNY_CORE_ERR_UNKNOWN,
} bunny_core_result_t;

const char *bunny_core_result_to_string(bunny_core_result_t result);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_CORE_ERROR_H */
