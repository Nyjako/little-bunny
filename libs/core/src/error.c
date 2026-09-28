#include "bunny_core/error.h"

const char *bunny_core_result_to_string(bunny_core_result_t result)
{
    switch (result) {
        case BUNNY_CORE_OK:
            return "ok";
        case BUNNY_CORE_ERR_INVALID_ARG:
            return "invalid argument";
        case BUNNY_CORE_ERR_NOT_FOUND:
            return "not found";
        case BUNNY_CORE_ERR_DB:
            return "database error";
        case BUNNY_CORE_ERR_UNKNOWN:
        default:
            return "unknown error";
    }
}
