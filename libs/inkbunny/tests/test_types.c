#include "unity.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "internal.h"

void setUp(void)
{}
void tearDown(void)
{}

static char *read_fixture(const char *filename)
{
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

void test_parse_submission_full(void)
{
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
    TEST_ASSERT_EQUAL(3951894, (int)submission.pools.items[0].left_submission_id);
    TEST_ASSERT_EQUAL(3956000, (int)submission.pools.items[0].right_submission_id);

    TEST_ASSERT_EQUAL(1, (int)submission.content_ratings.count);
    TEST_ASSERT_EQUAL_STRING("Nudity", submission.content_ratings.items[0].name);
    TEST_ASSERT_EQUAL(3, (int)submission.content_ratings.items[0].content_tag_id);

    inkbunny_submission_free(&submission);
    cJSON_Delete(root);
    free(content);
}

void test_parse_submission_missing_id_fails(void)
{
    cJSON *obj = cJSON_Parse("{\"title\": \"no id here\"}");
    TEST_ASSERT_NOT_NULL(obj);

    inkbunny_submission_t submission;
    inkbunny_result_t result = inkbunny_parse_submission(obj, &submission);
    TEST_ASSERT_EQUAL(INKBUNNY_ERR_PARSE, result);

    cJSON_Delete(obj);
}

void test_parse_submission_array_success(void)
{
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

void test_parse_submission_synthesizes_a_file_from_top_level_fields_when_files_array_is_absent(void)
{
    /* api_search.php's actual shape (confirmed against the live API,
     * 2026-11-05) -- file fields directly on the submission object, no
     * nested "files" array at all. Before this fallback existed,
     * files.count stayed 0 for every search-synced submission, so
     * file_url/file_ext/sample_url ended up NULL in the DB until a later
     * live per-submission refetch patched them up -- the detail view
     * showed nothing until that extra round trip finished. */
    cJSON *obj = cJSON_Parse("{\"submission_id\": \"42\", \"file_name\": \"42_artist_pic.jpg\", "
                             "\"file_url_full\": \"https://example.com/full/42.jpg\", "
                             "\"file_url_screen\": \"https://example.com/screen/42.jpg\", "
                             "\"file_url_preview\": \"https://example.com/preview/42.jpg\", "
                             "\"mimetype\": \"image/jpeg\"}");
    TEST_ASSERT_NOT_NULL(obj);

    inkbunny_submission_t submission;
    inkbunny_result_t result = inkbunny_parse_submission(obj, &submission);
    TEST_ASSERT_EQUAL(INKBUNNY_OK, result);
    TEST_ASSERT_EQUAL(1, (int)submission.files.count);
    TEST_ASSERT_EQUAL_STRING("42_artist_pic.jpg", submission.files.items[0].file_name);
    TEST_ASSERT_EQUAL_STRING("https://example.com/full/42.jpg", submission.files.items[0].url_full);
    TEST_ASSERT_EQUAL_STRING("https://example.com/screen/42.jpg", submission.files.items[0].url_screen);
    TEST_ASSERT_EQUAL_STRING("image/jpeg", submission.files.items[0].mimetype);
    /* Genuinely absent at this level, same as a real api_search.php
     * response -- the fallback must not invent these. */
    TEST_ASSERT_NULL(submission.files.items[0].md5);
    TEST_ASSERT_EQUAL(0, submission.files.items[0].full_width);
    TEST_ASSERT_EQUAL(0, submission.files.items[0].full_height);

    inkbunny_submission_free(&submission);
    cJSON_Delete(obj);
}

void test_parse_submission_leaves_files_empty_when_neither_shape_is_present(void)
{
    /* A submission with genuinely no file at all (e.g. a deleted/removed
     * one) must not synthesize a bogus entry. */
    cJSON *obj = cJSON_Parse("{\"submission_id\": \"42\", \"title\": \"no file here\"}");
    TEST_ASSERT_NOT_NULL(obj);

    inkbunny_submission_t submission;
    inkbunny_result_t result = inkbunny_parse_submission(obj, &submission);
    TEST_ASSERT_EQUAL(INKBUNNY_OK, result);
    TEST_ASSERT_EQUAL(0, (int)submission.files.count);

    inkbunny_submission_free(&submission);
    cJSON_Delete(obj);
}

void test_parse_submission_array_propagates_item_error(void)
{
    cJSON *array = cJSON_Parse("[{\"submission_id\": \"1\"}, {\"title\": \"no id\"}]");
    TEST_ASSERT_NOT_NULL(array);

    inkbunny_submission_list_t list;
    inkbunny_result_t result = inkbunny_parse_submission_array(array, &list);
    TEST_ASSERT_EQUAL(INKBUNNY_ERR_PARSE, result);

    cJSON_Delete(array);
}

void test_parse_submission_lenient_on_malformed_keywords(void)
{
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

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_parse_submission_full);
    RUN_TEST(test_parse_submission_missing_id_fails);
    RUN_TEST(test_parse_submission_array_success);
    RUN_TEST(test_parse_submission_array_propagates_item_error);
    RUN_TEST(test_parse_submission_lenient_on_malformed_keywords);
    RUN_TEST(test_parse_submission_synthesizes_a_file_from_top_level_fields_when_files_array_is_absent);
    RUN_TEST(test_parse_submission_leaves_files_empty_when_neither_shape_is_present);
    return UNITY_END();
}
