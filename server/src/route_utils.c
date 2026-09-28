#include "route_utils.h"

#include <stdlib.h>
#include <string.h>

const char *server_route_sub_path(const char *uri, const char *prefix)
{
    size_t prefix_len = strlen(prefix);
    if (strncmp(uri, prefix, prefix_len) != 0) {
        return NULL;
    }
    if (uri[prefix_len] != '/' || uri[prefix_len + 1] == '\0') {
        return NULL;
    }
    return uri + prefix_len + 1;
}

bool server_route_parse_id(const char *text, int64_t *out_id)
{
    if (!text || !*text) {
        return false;
    }
    char *end = NULL;
    long long value = strtoll(text, &end, 10);
    if (end == text || *end != '\0' || value <= 0) {
        return false;
    }
    *out_id = (int64_t)value;
    return true;
}

bool server_route_parse_id_with_suffix(const char *sub_path, const char *suffix, int64_t *out_id)
{
    const char *slash = strchr(sub_path, '/');
    if (!slash || strcmp(slash + 1, suffix) != 0) {
        return false;
    }

    size_t id_len = (size_t)(slash - sub_path);
    char id_buf[32];
    if (id_len == 0 || id_len >= sizeof(id_buf)) {
        return false;
    }
    memcpy(id_buf, sub_path, id_len);
    id_buf[id_len] = '\0';
    return server_route_parse_id(id_buf, out_id);
}

bool server_route_parse_site(const char *text, bunny_db_site_t *out_site)
{
    if (!text) {
        return false;
    }
    if (strcmp(text, "e621") == 0) {
        *out_site = BUNNY_DB_SITE_E621;
        return true;
    }
    if (strcmp(text, "inkbunny") == 0) {
        *out_site = BUNNY_DB_SITE_INKBUNNY;
        return true;
    }
    return false;
}
