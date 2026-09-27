#ifndef INKBUNNY_INTERNAL_H
#define INKBUNNY_INTERNAL_H

#include <bunny_common/json.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "inkbunny/error.h"
#include "inkbunny/types.h"

/* JSON <-> struct (de)serialization, shared between client.c and tests. */
inkbunny_result_t inkbunny_parse_submission(const cJSON *json, inkbunny_submission_t *out);
inkbunny_result_t inkbunny_parse_submission_array(const cJSON *json_array, inkbunny_submission_list_t *out);

/*
 * Inkbunny encodes every numeric field as a JSON string (e.g. "submission_id": "12345"),
 * and every boolean as the string "t" or "f", confirmed against the live API. These
 * helpers tolerate a real JSON number/bool too, in case that ever changes.
 */
static inline int64_t inkbunny_field_int64(const cJSON *object, const char *key, int64_t default_value) {
    if (!object || !cJSON_IsObject(object)) {
        return default_value;
    }
    cJSON *field = cJSON_GetObjectItemCaseSensitive(object, key);
    if (!field) {
        return default_value;
    }
    if (cJSON_IsNumber(field)) {
        return (int64_t)field->valuedouble;
    }
    if (cJSON_IsString(field) && field->valuestring) {
        return strtoll(field->valuestring, NULL, 10);
    }
    return default_value;
}

static inline int inkbunny_field_int(const cJSON *object, const char *key, int default_value) {
    return (int)inkbunny_field_int64(object, key, default_value);
}

static inline bool inkbunny_field_bool_tf(const cJSON *object, const char *key, bool default_value) {
    const char *value = bunny_json_get_string_or(object, key, NULL);
    if (!value) {
        return default_value;
    }
    if (strcmp(value, "t") == 0) {
        return true;
    }
    if (strcmp(value, "f") == 0) {
        return false;
    }
    return default_value;
}

#endif /* INKBUNNY_INTERNAL_H */
