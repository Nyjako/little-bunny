#ifndef E621_INTERNAL_H
#define E621_INTERNAL_H

#include <bunny_common/json.h>

#include "e621/error.h"
#include "e621/types.h"

/* JSON <-> struct (de)serialization, shared between client.c and tests. */

e621_result_t e621_parse_post(const cJSON *json, e621_post_t *out);
e621_result_t e621_parse_post_array(const cJSON *json_array, e621_post_list_t *out);
e621_result_t e621_parse_comment(const cJSON *json, e621_comment_t *out);
e621_result_t e621_parse_comment_array(const cJSON *json_array, e621_comment_list_t *out);
e621_result_t e621_parse_pool(const cJSON *json, e621_pool_t *out);
e621_result_t e621_parse_tag(const cJSON *json, e621_tag_t *out);
e621_result_t e621_parse_tag_array(const cJSON *json_array, e621_tag_list_t *out);
e621_result_t e621_parse_wiki_page(const cJSON *json, e621_wiki_page_t *out);
e621_result_t e621_parse_tag_alias(const cJSON *json, e621_tag_alias_t *out);
e621_result_t e621_parse_tag_alias_array(const cJSON *json_array, e621_tag_alias_list_t *out);
e621_result_t e621_parse_tag_implication(const cJSON *json, e621_tag_implication_t *out);
e621_result_t e621_parse_tag_implication_array(const cJSON *json_array, e621_tag_implication_list_t *out);

#endif /* E621_INTERNAL_H */
