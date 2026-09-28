#ifndef BUNNY_CORE_INTERNAL_H
#define BUNNY_CORE_INTERNAL_H

#include "bunny_core/core.h"
#include "bunny_core/error.h"
#include "bunny_db/db.h"

struct bunny_core
{
    bunny_db_t *db;
};

static inline bunny_core_result_t bunny_core_map_db_result(bunny_db_result_t result)
{
    switch (result) {
        case BUNNY_DB_OK:
            return BUNNY_CORE_OK;
        case BUNNY_DB_ERR_INVALID_ARG:
            return BUNNY_CORE_ERR_INVALID_ARG;
        case BUNNY_DB_ERR_NOT_FOUND:
            return BUNNY_CORE_ERR_NOT_FOUND;
        default:
            return BUNNY_CORE_ERR_DB;
    }
}

#endif /* BUNNY_CORE_INTERNAL_H */
