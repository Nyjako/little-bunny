#include "bunny_db/error.h"

const char *bunny_db_result_to_string(bunny_db_result_t result)
{
    switch (result) {
        case BUNNY_DB_OK:
            return "ok";
        case BUNNY_DB_ERR_INVALID_ARG:
            return "invalid argument";
        case BUNNY_DB_ERR_OPEN_FAILED:
            return "failed to open database";
        case BUNNY_DB_ERR_QUERY_FAILED:
            return "query failed";
        case BUNNY_DB_ERR_NOT_FOUND:
            return "not found";
        case BUNNY_DB_ERR_CONSTRAINT:
            return "constraint violation";
        case BUNNY_DB_ERR_UNKNOWN:
        default:
            return "unknown error";
    }
}
