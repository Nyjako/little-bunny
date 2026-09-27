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

void test_parse_submission_full(void) {
    char *content = read_fixture("submission_full.json");
    TEST_ASSERT_NOT_NULL(content);

    cJSON *root = cJSON_Parse(content);
    TEST_ASSERT_NOT_NULL(root);
    cJSON *submissions_array = cJSON_GetObjectItemCaseSensitive(root, "submissions");
    TEST_ASSERT_NOT_NULL(submissions_array);
    cJSON *submission_obj = cJSON_GetArrayItem(submissions_array, 0);
    TEST_ASSERT_NOT_NULL(submission_obj);

    inkbunny_submission_t submission;
    inkbunny_result_t result = inkbunny_parse_submission(submission_obj, &submission);
    TEST_ASSERT_EQUAL(INKBUNNY_OK, result);

    /* submission_id is JSON-encoded as a string ("3955918"); confirms our
     * string-tolerant numeric parsing works. */
    TEST_ASSERT_EQUAL(3955918, (int)submission.submission_id);
    TEST_ASSERT_EQUAL_STRING("OvineSatanOMG", submission.username);
    TEST_ASSERT_EQUAL(628881, (int)submission.user_id);
    TEST_ASSERT_EQUAL_STRING("Thank you, Digimon Beatbreak", submission.title);
    TEST_ASSERT_EQUAL(1, submission.rating_id);
    TEST_ASSERT_EQUAL_STRING("Mature", submission.rating_name);

    /* "favorite": "t" -> true; confirms our "t"/"f" boolean parsing works. */
    TEST_ASSERT_TRUE(submission.is_favorite);
    TEST_ASSERT_EQUAL(1, submission.favorites_count);
    TEST_ASSERT_EQUAL(4, submission.comments_count);
    TEST_ASSERT_EQUAL(7, submission.views);

    TEST_ASSERT_EQUAL(3, (int)submission.keywords.count);
    TEST_ASSERT_EQUAL_STRING("digital", submission.keywords.items[0].keyword_name);
    TEST_ASSERT_FALSE(submission.keywords.items[0].contributed);
    TEST_ASSERT_TRUE(submission.keywords.items[2].contributed);

    TEST_ASSERT_EQUAL(1, (int)submission.files.count);
    TEST_ASSERT_EQUAL_STRING("7669594067d7153074250653c72ad34b", submission.files.items[0].md5);
    TEST_ASSERT_EQUAL(3385, submission.files.items[0].full_width);

    TEST_ASSERT_EQUAL(1, (int)submission.pools.count);
    TEST_ASSERT_EQUAL_STRING("Digimon Tributes", submission.pools.items[0].name);

    TEST_ASSERT_EQUAL(1, (int)submission.content_ratings.count);
    TEST_ASSERT_EQUAL_STRING("Nudity", submission.content_ratings.items[0].name);
    TEST_ASSERT_EQUAL(3, (int)submission.content_ratings.items[0].content_tag_id);

    inkbunny_submission_free(&submission);
    cJSON_Delete(root);
    free(content);
}

void test_parse_submission_missing_id_fails(void) {
    cJSON *obj = cJSON_Parse("{\"title\": \"no id here\"}");
    TEST_ASSERT_NOT_NULL(obj);

    inkbunny_submission_t submission;
    inkbunny_result_t result = inkbunny_parse_submission(obj, &submission);
    TEST_ASSERT_EQUAL(INKBUNNY_ERR_PARSE, result);

    cJSON_Delete(obj);
}

void test_parse_submission_array_success(void) {
    char *content = read_fixture("search_response.json");
    TEST_ASSERT_NOT_NULL(content);
    cJSON *root = cJSON_Parse(content);
    TEST_ASSERT_NOT_NULL(root);
    cJSON *submissions_array = cJSON_GetObjectItemCaseSensitive(root, "submissions");
    TEST_ASSERT_NOT_NULL(submissions_array);

    inkbunny_submission_list_t list;
    inkbunny_result_t result = inkbunny_parse_submission_array(submissions_array, &list);
    TEST_ASSERT_EQUAL(INKBUNNY_OK, result);
    TEST_ASSERT_EQUAL(2, (int)list.count);
    TEST_ASSERT_EQUAL_STRING("OvineSatanOMG", list.items[0].username);
    TEST_ASSERT_EQUAL_STRING("BengalBatEmmaKat", list.items[1].username);

    inkbunny_submission_list_free(&list);
    cJSON_Delete(root);
    free(content);
}

void test_parse_submission_array_propagates_item_error(void) {
    cJSON *array = cJSON_Parse("[{\"submission_id\": \"1\"}, {\"title\": \"no id\"}]");
    TEST_ASSERT_NOT_NULL(array);

    inkbunny_submission_list_t list;
    inkbunny_result_t result = inkbunny_parse_submission_array(array, &list);
    TEST_ASSERT_EQUAL(INKBUNNY_ERR_PARSE, result);

    cJSON_Delete(array);
}

void test_parse_submission_lenient_on_malformed_keywords(void) {
    /* "keywords" isn't an array here; parsing should still succeed with an
     * empty keyword list rather than failing the whole submission. */
    cJSON *obj = cJSON_Parse("{\"submission_id\": \"1\", \"keywords\": \"not-an-array\"}");
    TEST_ASSERT_NOT_NULL(obj);

    inkbunny_submission_t submission;
    inkbunny_result_t result = inkbunny_parse_submission(obj, &submission);
    TEST_ASSERT_EQUAL(INKBUNNY_OK, result);
    TEST_ASSERT_EQUAL(0, (int)submission.keywords.count);

    inkbunny_submission_free(&submission);
    cJSON_Delete(obj);
}

int main(void) {
    UNITY_BEGIN();
    RUN_TEST(test_parse_submission_full);
    RUN_TEST(test_parse_submission_missing_id_fails);
    RUN_TEST(test_parse_submission_array_success);
    RUN_TEST(test_parse_submission_array_propagates_item_error);
    RUN_TEST(test_parse_submission_lenient_on_malformed_keywords);
    return UNITY_END();
}
