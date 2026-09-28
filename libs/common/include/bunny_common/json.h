#ifndef BUNNY_COMMON_JSON_H
#define BUNNY_COMMON_JSON_H

#include <cJSON.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum
{
    BUNNY_JSON_OK = 0,
    BUNNY_JSON_ERR_MISSING,
    BUNNY_JSON_ERR_TYPE,
} bunny_json_result_t;

/*
 * Field accessors that fail loudly and predictably on malformed input
 * (missing key, wrong type) instead of letting a NULL cJSON* propagate into
 * a segfault. `object` may be NULL, which is treated as BUNNY_JSON_ERR_MISSING.
 */
bunny_json_result_t bunny_json_get_object(const cJSON *object, const char *key, cJSON **out);
bunny_json_result_t bunny_json_get_array(const cJSON *object, const char *key, cJSON **out);
bunny_json_result_t bunny_json_get_string(const cJSON *object, const char *key, const char **out);
bunny_json_result_t bunny_json_get_int(const cJSON *object, const char *key, int *out);
bunny_json_result_t bunny_json_get_int64(const cJSON *object, const char *key, int64_t *out);
bunny_json_result_t bunny_json_get_bool(const cJSON *object, const char *key, bool *out);

/* Same as above, but a missing key yields the given default instead of an error. */
const char *bunny_json_get_string_or(const cJSON *object, const char *key, const char *default_value);
int bunny_json_get_int_or(const cJSON *object, const char *key, int default_value);
bool bunny_json_get_bool_or(const cJSON *object, const char *key, bool default_value);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_COMMON_JSON_H */
