#include "unity.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "internal.h"

void setUp(void) {}
void tearDown(void) {}

static char *read_fixture(const char *filename) {
    char path[512];
    snprintf(path, sizeof(path), "%s/%s", FIXTURES_DIR, filename);

    FILE *f = fopen(path, "rb");
    if (!f) {
        return NULL;
    }
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    char *buf = malloc((size_t)size + 1);
    if (!buf) {
        fclose(f);
        return NULL;
    }
    if (fread(buf, 1, (size_t)size, f) != (size_t)size) {
        fclose(f);
        free(buf);
        return NULL;
    }
    buf[size] = '\0';
    fclose(f);
    return buf;
}

void test_parse_post_full(void) {
    char *content = read_fixture("post_single.json");
    TEST_ASSERT_NOT_NULL(content);

    cJSON *root = cJSON_Parse(content);
    TEST_ASSERT_NOT_NULL(root);
    cJSON *post_obj = cJSON_GetObjectItemCaseSensitive(root, "post");
    TEST_ASSERT_NOT_NULL(post_obj);

    e621_post_t post;
    e621_result_t result = e621_parse_post(post_obj, &post);
    TEST_ASSERT_EQUAL(E621_OK, result);

    TEST_ASSERT_EQUAL(12345, (int)post.id);
    TEST_ASSERT_EQUAL_STRING("jpg", post.file.ext);
    TEST_ASSERT_EQUAL(1920, post.file.width);
    TEST_ASSERT_EQUAL(39, post.score.total);
    TEST_ASSERT_EQUAL(128, post.fav_count);
    TEST_ASSERT_TRUE(post.is_favorited);
    TEST_ASSERT_EQUAL(E621_RATING_SAFE, post.rating);
    TEST_ASSERT_EQUAL(3, (int)post.tags.general.count);
    TEST_ASSERT_EQUAL(2, (int)post.tags.species.count);
    TEST_ASSERT_EQUAL_STRING("canine", post.tags.species.items[0]);
    TEST_ASSERT_EQUAL(1, (int)post.sources.count);
    TEST_ASSERT_EQUAL(2, (int)post.pool_count);
    TEST_ASSERT_EQUAL(10, (int)post.pool_ids[0]);

    e621_post_free(&post);
    cJSON_Delete(root);
    free(content);
}

void test_parse_post_missing_id_fails(void) {
    cJSON *obj = cJSON_Parse("{\"created_at\": \"now\"}");
    TEST_ASSERT_NOT_NULL(obj);

    e621_post_t post;
    e621_result_t result = e621_parse_post(obj, &post);
    TEST_ASSERT_EQUAL(E621_ERR_PARSE, result);

    cJSON_Delete(obj);
}

void test_parse_post_array_success(void) {
    char *content = read_fixture("posts_search.json");
    TEST_ASSERT_NOT_NULL(content);
    cJSON *root = cJSON_Parse(content);
    TEST_ASSERT_NOT_NULL(root);
    cJSON *posts_array = cJSON_GetObjectItemCaseSensitive(root, "posts");
    TEST_ASSERT_NOT_NULL(posts_array);

    e621_post_list_t list;
    e621_result_t result = e621_parse_post_array(posts_array, &list);
    TEST_ASSERT_EQUAL(E621_OK, result);
    TEST_ASSERT_EQUAL(2, (int)list.count);

    e621_post_list_free(&list);
    cJSON_Delete(root);
    free(content);
}

void test_parse_post_array_propagates_item_error(void) {
    cJSON *array = cJSON_Parse("[{\"id\": 1}, {\"no_id\": true}]");
    TEST_ASSERT_NOT_NULL(array);

    e621_post_list_t list;
    e621_result_t result = e621_parse_post_array(array, &list);
    TEST_ASSERT_EQUAL(E621_ERR_PARSE, result);

    cJSON_Delete(array);
}

void test_parse_comment_array_success(void) {
    char *content = read_fixture("comments_list.json");
    TEST_ASSERT_NOT_NULL(content);
    cJSON *array = cJSON_Parse(content);
    TEST_ASSERT_NOT_NULL(array);

    e621_comment_list_t comments;
    e621_result_t result = e621_parse_comment_array(array, &comments);
    TEST_ASSERT_EQUAL(E621_OK, result);
    TEST_ASSERT_EQUAL(2, (int)comments.count);
    TEST_ASSERT_EQUAL_STRING("Nice pic!", comments.items[0].body);

    e621_comment_list_free(&comments);
    cJSON_Delete(array);
    free(content);
}

void test_parse_post_lenient_on_malformed_tag_category(void) {
    /* "general" isn't an array here; parsing should still succeed with an
     * empty general list rather than failing the whole post. */
    cJSON *obj = cJSON_Parse("{\"id\": 1, \"tags\": {\"general\": \"not-an-array\"}}");
    TEST_ASSERT_NOT_NULL(obj);

    e621_post_t post;
    e621_result_t result = e621_parse_post(obj, &post);
    TEST_ASSERT_EQUAL(E621_OK, result);
    TEST_ASSERT_EQUAL(0, (int)post.tags.general.count);

    e621_post_free(&post);
    cJSON_Delete(obj);
}

int main(void) {
    UNITY_BEGIN();
    RUN_TEST(test_parse_post_full);
    RUN_TEST(test_parse_post_missing_id_fails);
    RUN_TEST(test_parse_post_array_success);
    RUN_TEST(test_parse_post_array_propagates_item_error);
    RUN_TEST(test_parse_comment_array_success);
    RUN_TEST(test_parse_post_lenient_on_malformed_tag_category);
    return UNITY_END();
}
