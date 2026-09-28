#ifndef BUNNY_DB_ERROR_H
#define BUNNY_DB_ERROR_H

#ifdef __cplusplus
extern "C" {
#endif

typedef enum
{
    BUNNY_DB_OK = 0,
    BUNNY_DB_ERR_INVALID_ARG,
    BUNNY_DB_ERR_OPEN_FAILED,
    BUNNY_DB_ERR_QUERY_FAILED,
    BUNNY_DB_ERR_NOT_FOUND,
    BUNNY_DB_ERR_CONSTRAINT, /* e.g. a UNIQUE violation */
    BUNNY_DB_ERR_UNKNOWN,
} bunny_db_result_t;

const char *bunny_db_result_to_string(bunny_db_result_t result);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_DB_ERROR_H */
