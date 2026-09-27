#include "e621/error.h"

const char *e621_result_to_string(e621_result_t result) {
    switch (result) {
        case E621_OK:
            return "ok";
        case E621_ERR_INVALID_ARG:
            return "invalid argument";
        case E621_ERR_NETWORK:
            return "network error";
        case E621_ERR_AUTH:
            return "authentication failed";
        case E621_ERR_NOT_FOUND:
            return "not found";
        case E621_ERR_RATE_LIMITED:
            return "rate limited";
        case E621_ERR_PARSE:
            return "failed to parse response";
        case E621_ERR_SERVER:
            return "server error";
        case E621_ERR_UNKNOWN:
        default:
            return "unknown error";
    }
}
