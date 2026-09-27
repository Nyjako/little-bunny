#include "inkbunny/error.h"

const char *inkbunny_result_to_string(inkbunny_result_t result) {
    switch (result) {
        case INKBUNNY_OK:
            return "ok";
        case INKBUNNY_ERR_INVALID_ARG:
            return "invalid argument";
        case INKBUNNY_ERR_NETWORK:
            return "network error";
        case INKBUNNY_ERR_AUTH:
            return "authentication failed";
        case INKBUNNY_ERR_NOT_FOUND:
            return "not found";
        case INKBUNNY_ERR_RATE_LIMITED:
            return "rate limited";
        case INKBUNNY_ERR_PARSE:
            return "failed to parse response";
        case INKBUNNY_ERR_SERVER:
            return "server error";
        case INKBUNNY_ERR_UNKNOWN:
        default:
            return "unknown error";
    }
}
