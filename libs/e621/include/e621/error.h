#ifndef E621_ERROR_H
#define E621_ERROR_H

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    E621_OK = 0,
    E621_ERR_INVALID_ARG,
    E621_ERR_NETWORK,
    E621_ERR_AUTH,
    E621_ERR_NOT_FOUND,
    E621_ERR_RATE_LIMITED,
    E621_ERR_PARSE,
    E621_ERR_SERVER,
    E621_ERR_UNKNOWN,
} e621_result_t;

const char *e621_result_to_string(e621_result_t result);

#ifdef __cplusplus
}
#endif

#endif /* E621_ERROR_H */
