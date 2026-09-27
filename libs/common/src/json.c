#include "bunny_common/json.h"

bunny_json_result_t bunny_json_get_object(const cJSON *object, const char *key, cJSON **out) {
    if (!object || !cJSON_IsObject(object)) {
        return BUNNY_JSON_ERR_MISSING;
    }
    cJSON *field = cJSON_GetObjectItemCaseSensitive(object, key);
    if (!field) {
        return BUNNY_JSON_ERR_MISSING;
    }
    if (!cJSON_IsObject(field)) {
        return BUNNY_JSON_ERR_TYPE;
    }
    *out = field;
    return BUNNY_JSON_OK;
}

bunny_json_result_t bunny_json_get_array(const cJSON *object, const char *key, cJSON **out) {
    if (!object || !cJSON_IsObject(object)) {
        return BUNNY_JSON_ERR_MISSING;
    }
    cJSON *field = cJSON_GetObjectItemCaseSensitive(object, key);
    if (!field) {
        return BUNNY_JSON_ERR_MISSING;
    }
    if (!cJSON_IsArray(field)) {
        return BUNNY_JSON_ERR_TYPE;
    }
    *out = field;
    return BUNNY_JSON_OK;
}

bunny_json_result_t bunny_json_get_string(const cJSON *object, const char *key, const char **out) {
    if (!object || !cJSON_IsObject(object)) {
        return BUNNY_JSON_ERR_MISSING;
    }
    cJSON *field = cJSON_GetObjectItemCaseSensitive(object, key);
    if (!field) {
        return BUNNY_JSON_ERR_MISSING;
    }
    if (!cJSON_IsString(field) || !field->valuestring) {
        return BUNNY_JSON_ERR_TYPE;
    }
    *out = field->valuestring;
    return BUNNY_JSON_OK;
}

bunny_json_result_t bunny_json_get_int(const cJSON *object, const char *key, int *out) {
    if (!object || !cJSON_IsObject(object)) {
        return BUNNY_JSON_ERR_MISSING;
    }
    cJSON *field = cJSON_GetObjectItemCaseSensitive(object, key);
    if (!field) {
        return BUNNY_JSON_ERR_MISSING;
    }
    if (!cJSON_IsNumber(field)) {
        return BUNNY_JSON_ERR_TYPE;
    }
    *out = field->valueint;
    return BUNNY_JSON_OK;
}

bunny_json_result_t bunny_json_get_int64(const cJSON *object, const char *key, int64_t *out) {
    if (!object || !cJSON_IsObject(object)) {
        return BUNNY_JSON_ERR_MISSING;
    }
    cJSON *field = cJSON_GetObjectItemCaseSensitive(object, key);
    if (!field) {
        return BUNNY_JSON_ERR_MISSING;
    }
    if (!cJSON_IsNumber(field)) {
        return BUNNY_JSON_ERR_TYPE;
    }
    *out = (int64_t)field->valuedouble;
    return BUNNY_JSON_OK;
}

bunny_json_result_t bunny_json_get_bool(const cJSON *object, const char *key, bool *out) {
    if (!object || !cJSON_IsObject(object)) {
        return BUNNY_JSON_ERR_MISSING;
    }
    cJSON *field = cJSON_GetObjectItemCaseSensitive(object, key);
    if (!field) {
        return BUNNY_JSON_ERR_MISSING;
    }
    if (!cJSON_IsBool(field)) {
        return BUNNY_JSON_ERR_TYPE;
    }
    *out = cJSON_IsTrue(field);
    return BUNNY_JSON_OK;
}

const char *bunny_json_get_string_or(const cJSON *object, const char *key, const char *default_value) {
    const char *value = NULL;
    if (bunny_json_get_string(object, key, &value) != BUNNY_JSON_OK) {
        return default_value;
    }
    return value;
}

int bunny_json_get_int_or(const cJSON *object, const char *key, int default_value) {
    int value = 0;
    if (bunny_json_get_int(object, key, &value) != BUNNY_JSON_OK) {
        return default_value;
    }
    return value;
}

bool bunny_json_get_bool_or(const cJSON *object, const char *key, bool default_value) {
    bool value = false;
    if (bunny_json_get_bool(object, key, &value) != BUNNY_JSON_OK) {
        return default_value;
    }
    return value;
}
