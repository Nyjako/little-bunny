#include "unity.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "bunny_core/core.h"

typedef struct
{
    const char *body;
    long status;
} fake_transport_state_t;

static fake_transport_state_t g_e621_state;
static bunny_http_transport_t g_e621_transport;
static bunny_core_t *g_core;

static bunny_http_result_t fake_send(void *user_data, const bunny_http_request_t *request, bunny_http_response_t *out_response)
{
    (void)request;
    fake_transport_state_t *state = (fake_transport_state_t *)user_data;
    out_response->status = state->status;
    const char *body = state->body ? state->body : "";
    out_response->body = strdup(body);
    out_response->body_len = strlen(body);
    return BUNNY_HTTP_OK;
}

void setUp(void)
{
    memset(&g_e621_state, 0, sizeof(g_e621_state));
    g_e621_state.status = 200;
    g_e621_transport.send = fake_send;
    g_e621_transport.user_data = &g_e621_state;

    bunny_core_config_t config;
    memset(&config, 0, sizeof(config));
    config.db_path = ":memory:";
    config.user_agent = "bunny-tests/1.0 (unit tests)";
    config.e621_transport = &g_e621_transport;
    config.min_request_interval_sec = 0.001;

    bunny_core_result_t result = bunny_core_open(&config, &g_core);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
}

void tearDown(void)
{
    bunny_core_close(g_core);
    g_core = NULL;
}

void test_search_tags_maps_results(void)
{
    g_e621_state.body =
        "[{\"id\":1,\"name\":\"fox\",\"post_count\":12345,\"category\":5,\"related_tags\":\"canine wolf\",\"is_locked\":false,"
        "\"created_at\":\"2020-01-01T00:00:00.000-05:00\",\"updated_at\":\"2020-01-02T00:00:00.000-05:00\"}]";

    bunny_core_tag_list_t tags;
    bunny_core_result_t result = bunny_core_search_tags(g_core, "fox", 0, &tags);

    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, (int)tags.count);
    TEST_ASSERT_EQUAL_STRING("fox", tags.items[0].name);
    TEST_ASSERT_EQUAL(12345, tags.items[0].post_count);
    TEST_ASSERT_EQUAL(BUNNY_CORE_TAG_CATEGORY_SPECIES, tags.items[0].category);

    bunny_core_tag_list_free(&tags);
}

void test_search_tags_invalid_arg(void)
{
    bunny_core_result_t result = bunny_core_search_tags(NULL, "fox", 0, NULL);
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_INVALID_ARG, result);
}

void test_get_wiki_page_maps_result(void)
{
    g_e621_state.body =
        "[{\"id\":7,\"title\":\"fox\",\"body\":\"A [[canine]] species. See {{author}} for art.\","
        "\"other_names\":[\"foxes\"],\"is_locked\":false,\"created_at\":\"2020-01-01T00:00:00.000-05:00\","
        "\"updated_at\":\"2020-01-02T00:00:00.000-05:00\"}]";

    bunny_core_wiki_page_t page;
    bunny_core_result_t result = bunny_core_get_wiki_page(g_core, "fox", &page);

    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL_STRING("fox", page.title);
    TEST_ASSERT_EQUAL_STRING("A [[canine]] species. See {{author}} for art.", page.body);
    TEST_ASSERT_EQUAL(1, (int)page.other_names.count);
    TEST_ASSERT_EQUAL_STRING("foxes", page.other_names.items[0]);

    bunny_core_wiki_page_free(&page);
}

void test_get_wiki_page_not_found(void)
{
    g_e621_state.body = "[]";

    bunny_core_wiki_page_t page;
    bunny_core_result_t result = bunny_core_get_wiki_page(g_core, "no_such_tag_at_all", &page);

    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_NOT_FOUND, result);
}

void test_search_tag_aliases_maps_results(void)
{
    g_e621_state.body = "[{\"id\":1,\"antecedent_name\":\"foxes\",\"consequent_name\":\"fox\",\"status\":\"active\",\"post_count\":12345}]";

    bunny_core_tag_alias_list_t aliases;
    bunny_core_result_t result = bunny_core_search_tag_aliases(g_core, "fox", 0, &aliases);

    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, (int)aliases.count);
    TEST_ASSERT_EQUAL_STRING("foxes", aliases.items[0].antecedent_name);
    TEST_ASSERT_EQUAL_STRING("fox", aliases.items[0].consequent_name);

    bunny_core_tag_alias_list_free(&aliases);
}

void test_search_tag_implications_maps_results(void)
{
    g_e621_state.body = "[{\"id\":1,\"antecedent_name\":\"red_fox\",\"consequent_name\":\"fox\",\"status\":\"active\"}]";

    bunny_core_tag_implication_list_t implications;
    bunny_core_result_t result = bunny_core_search_tag_implications(g_core, "red_fox", 0, &implications);

    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, (int)implications.count);
    TEST_ASSERT_EQUAL_STRING("red_fox", implications.items[0].antecedent_name);
    TEST_ASSERT_EQUAL_STRING("fox", implications.items[0].consequent_name);

    bunny_core_tag_implication_list_free(&implications);
}

void test_site_error_maps_to_err_site(void)
{
    g_e621_state.status = 500;
    g_e621_state.body = "";

    bunny_core_tag_list_t tags;
    bunny_core_result_t result = bunny_core_search_tags(g_core, "fox", 0, &tags);

    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_SITE, result);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_search_tags_maps_results);
    RUN_TEST(test_search_tags_invalid_arg);
    RUN_TEST(test_get_wiki_page_maps_result);
    RUN_TEST(test_get_wiki_page_not_found);
    RUN_TEST(test_search_tag_aliases_maps_results);
    RUN_TEST(test_search_tag_implications_maps_results);
    RUN_TEST(test_site_error_maps_to_err_site);
    return UNITY_END();
}
