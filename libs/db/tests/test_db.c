#include "unity.h"

#include <stdio.h>
#include <string.h>

#include "bunny_db/db.h"

static bunny_db_t *g_db;

void setUp(void)
{
    bunny_db_result_t result = bunny_db_open(":memory:", &g_db);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_NOT_NULL(g_db);
}

void tearDown(void)
{
    bunny_db_close(g_db);
    g_db = NULL;
}

void test_open_close(void)
{
    /* setUp/tearDown already exercise this; just confirm double-close is safe. */
    bunny_db_close(NULL);
}

void test_search_create_and_list(void)
{
    int64_t id = 0;
    bunny_db_result_t result = bunny_db_search_create(g_db, BUNNY_DB_SITE_E621, "wolves", "wolf rating:s", 12, NULL, &id);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_TRUE(id > 0);

    bunny_db_search_list_t list;
    result = bunny_db_search_list(g_db, &list);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_EQUAL(1, (int)list.count);
    TEST_ASSERT_EQUAL(id, list.items[0].id);
    TEST_ASSERT_EQUAL(BUNNY_DB_SITE_E621, list.items[0].site);
    TEST_ASSERT_EQUAL_STRING("wolves", list.items[0].label);
    TEST_ASSERT_EQUAL_STRING("wolf rating:s", list.items[0].query);
    TEST_ASSERT_EQUAL(12, list.items[0].interval_hours);
    TEST_ASSERT_NULL(list.items[0].last_run_at);
    TEST_ASSERT_EQUAL(0, list.items[0].unseen_count);
    TEST_ASSERT_FALSE(list.items[0].auto_favorite);

    bunny_db_search_list_free(&list);
}

void test_search_create_with_auto_favorite(void)
{
    int64_t id = 0;
    bunny_db_search_options_t options = {true, 2, false};
    bunny_db_result_t result = bunny_db_search_create(g_db, BUNNY_DB_SITE_E621, "wolves", "wolf", 24, &options, &id);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);

    bunny_db_search_list_t list;
    bunny_db_search_list(g_db, &list);
    TEST_ASSERT_TRUE(list.items[0].auto_favorite);
    TEST_ASSERT_EQUAL(2, list.items[0].auto_favorite_stars);
    TEST_ASSERT_FALSE(list.items[0].auto_upvote);
    bunny_db_search_list_free(&list);
}

void test_search_create_defaults_auto_favorite_stars_to_one(void)
{
    int64_t id = 0;
    bunny_db_result_t result = bunny_db_search_create(g_db, BUNNY_DB_SITE_E621, "wolves", "wolf", 24, NULL, &id);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);

    bunny_db_search_list_t list;
    bunny_db_search_list(g_db, &list);
    TEST_ASSERT_EQUAL(1, list.items[0].auto_favorite_stars);
    bunny_db_search_list_free(&list);
}

void test_search_update_modifies_label_query_interval_and_options(void)
{
    int64_t id = 0;
    bunny_db_search_create(g_db, BUNNY_DB_SITE_E621, "wolves", "wolf", 24, NULL, &id);

    bunny_db_search_options_t options = {true, 3, true};
    bunny_db_result_t result = bunny_db_search_update(g_db, id, "renamed", "fox", 12, &options);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);

    bunny_db_search_list_t list;
    bunny_db_search_list(g_db, &list);
    TEST_ASSERT_EQUAL_STRING("renamed", list.items[0].label);
    TEST_ASSERT_EQUAL_STRING("fox", list.items[0].query);
    TEST_ASSERT_EQUAL(12, list.items[0].interval_hours);
    TEST_ASSERT_TRUE(list.items[0].auto_favorite);
    TEST_ASSERT_EQUAL(3, list.items[0].auto_favorite_stars);
    TEST_ASSERT_TRUE(list.items[0].auto_upvote);
    bunny_db_search_list_free(&list);

    bunny_db_search_options_t cleared = {false, 1, false};
    result = bunny_db_search_update(g_db, id, "renamed", "fox", 12, &cleared);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    bunny_db_search_list(g_db, &list);
    TEST_ASSERT_FALSE(list.items[0].auto_favorite);
    TEST_ASSERT_FALSE(list.items[0].auto_upvote);
    bunny_db_search_list_free(&list);
}

void test_search_default_interval(void)
{
    int64_t id = 0;
    bunny_db_result_t result = bunny_db_search_create(g_db, BUNNY_DB_SITE_INKBUNNY, "cats", "cat", 0, NULL, &id);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);

    bunny_db_search_list_t list;
    bunny_db_search_list(g_db, &list);
    TEST_ASSERT_EQUAL(24, list.items[0].interval_hours);
    bunny_db_search_list_free(&list);
}

void test_search_delete(void)
{
    int64_t id = 0;
    bunny_db_search_create(g_db, BUNNY_DB_SITE_E621, "temp", "temp", 24, NULL, &id);

    bunny_db_result_t result = bunny_db_search_delete(g_db, id);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);

    bunny_db_search_list_t list;
    bunny_db_search_list(g_db, &list);
    TEST_ASSERT_EQUAL(0, (int)list.count);
    bunny_db_search_list_free(&list);
}

void test_search_touch_last_run(void)
{
    int64_t id = 0;
    bunny_db_search_create(g_db, BUNNY_DB_SITE_E621, "temp", "temp", 24, NULL, &id);

    bunny_db_result_t result = bunny_db_search_touch_last_run(g_db, id);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);

    bunny_db_search_list_t list;
    bunny_db_search_list(g_db, &list);
    TEST_ASSERT_NOT_NULL(list.items[0].last_run_at);
    bunny_db_search_list_free(&list);
}

void test_account_set_and_get(void)
{
    bunny_db_result_t result = bunny_db_account_set(g_db, BUNNY_DB_SITE_E621, "someuser", "someapikey");
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);

    bunny_db_account_t account;
    result = bunny_db_account_get(g_db, BUNNY_DB_SITE_E621, &account);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_EQUAL_STRING("someuser", account.username);
    TEST_ASSERT_EQUAL_STRING("someapikey", account.secret);
    bunny_db_account_free(&account);
}

void test_account_set_upserts_by_site(void)
{
    bunny_db_account_set(g_db, BUNNY_DB_SITE_E621, "user1", "secret1");
    bunny_db_account_set(g_db, BUNNY_DB_SITE_E621, "user2", "secret2");

    bunny_db_account_t account;
    bunny_db_account_get(g_db, BUNNY_DB_SITE_E621, &account);
    TEST_ASSERT_EQUAL_STRING("user2", account.username);
    TEST_ASSERT_EQUAL_STRING("secret2", account.secret);
    bunny_db_account_free(&account);
}

void test_account_get_not_found(void)
{
    bunny_db_account_t account;
    bunny_db_result_t result = bunny_db_account_get(g_db, BUNNY_DB_SITE_INKBUNNY, &account);
    TEST_ASSERT_EQUAL(BUNNY_DB_ERR_NOT_FOUND, result);
}

void test_account_delete(void)
{
    bunny_db_account_set(g_db, BUNNY_DB_SITE_E621, "user", "secret");

    bunny_db_result_t result = bunny_db_account_delete(g_db, BUNNY_DB_SITE_E621);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);

    bunny_db_account_t account;
    result = bunny_db_account_get(g_db, BUNNY_DB_SITE_E621, &account);
    TEST_ASSERT_EQUAL(BUNNY_DB_ERR_NOT_FOUND, result);
}

void test_account_is_per_site(void)
{
    bunny_db_account_set(g_db, BUNNY_DB_SITE_E621, "e621user", "e621secret");
    bunny_db_account_set(g_db, BUNNY_DB_SITE_INKBUNNY, "ibuser", "ibsecret");

    bunny_db_account_t e621_account;
    bunny_db_account_get(g_db, BUNNY_DB_SITE_E621, &e621_account);
    TEST_ASSERT_EQUAL_STRING("e621user", e621_account.username);
    bunny_db_account_free(&e621_account);

    bunny_db_account_t ib_account;
    bunny_db_account_get(g_db, BUNNY_DB_SITE_INKBUNNY, &ib_account);
    TEST_ASSERT_EQUAL_STRING("ibuser", ib_account.username);
    bunny_db_account_free(&ib_account);
}

static void make_test_post(bunny_db_post_upsert_t *post, int64_t external_id, int score)
{
    memset(post, 0, sizeof(*post));
    post->site = BUNNY_DB_SITE_E621;
    post->external_id = external_id;
    post->artist = "someartist";
    post->title = NULL;
    post->description = "a test post";
    post->rating = "s";
    post->score = score;
    post->score_up = score + 2;
    post->score_down = 2;
    post->fav_count = 5;
    post->comment_count = 1;
    post->file_url = "https://example.com/file.jpg";
    post->file_ext = "jpg";
    post->file_md5 = "abc123";
    post->preview_url = "https://example.com/preview.jpg";
    post->width = 1920;
    post->height = 1080;
    post->created_at_site = "2026-01-01T00:00:00Z";
}

void test_search_list_unseen_count(void)
{
    int64_t search1_id = 0;
    int64_t search2_id = 0;
    bunny_db_search_create(g_db, BUNNY_DB_SITE_E621, "wolves", "wolf", 24, NULL, &search1_id);
    bunny_db_search_create(g_db, BUNNY_DB_SITE_E621, "foxes", "fox", 24, NULL, &search2_id);

    bunny_db_post_upsert_t post1;
    bunny_db_post_upsert_t post2;
    bunny_db_post_upsert_t post3;
    make_test_post(&post1, 911, 1);
    make_test_post(&post2, 912, 1);
    make_test_post(&post3, 913, 1);
    int64_t post1_id = 0;
    int64_t post2_id = 0;
    int64_t post3_id = 0;
    bunny_db_post_upsert(g_db, &post1, &post1_id);
    bunny_db_post_upsert(g_db, &post2, &post2_id);
    bunny_db_post_upsert(g_db, &post3, &post3_id);

    /* search1: two posts, one seen -> 1 unseen. search2: one post, untouched
     * -> 1 unseen. Each search's count must only reflect its own posts. */
    bunny_db_search_add_result(g_db, search1_id, post1_id);
    bunny_db_search_add_result(g_db, search1_id, post2_id);
    bunny_db_search_add_result(g_db, search2_id, post3_id);
    bunny_db_post_mark_seen(g_db, post1_id);

    bunny_db_search_list_t list;
    bunny_db_result_t result = bunny_db_search_list(g_db, &list);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_EQUAL(2, (int)list.count);
    TEST_ASSERT_EQUAL(search1_id, list.items[0].id);
    TEST_ASSERT_EQUAL(1, list.items[0].unseen_count);
    TEST_ASSERT_EQUAL(search2_id, list.items[1].id);
    TEST_ASSERT_EQUAL(1, list.items[1].unseen_count);

    bunny_db_search_list_free(&list);
}

void test_post_upsert_and_get(void)
{
    const char *tags[] = {"forest", "wolf"};
    bunny_db_post_upsert_t post;
    make_test_post(&post, 111, 10);
    post.tags = tags;
    post.tag_count = 2;

    int64_t id = 0;
    bunny_db_result_t result = bunny_db_post_upsert(g_db, &post, &id);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_TRUE(id > 0);

    bunny_db_post_t fetched;
    result = bunny_db_post_get(g_db, BUNNY_DB_SITE_E621, 111, &fetched);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_EQUAL(id, fetched.id);
    TEST_ASSERT_EQUAL_STRING("someartist", fetched.artist);
    TEST_ASSERT_NULL(fetched.title);
    TEST_ASSERT_EQUAL_STRING("abc123", fetched.file_md5);
    TEST_ASSERT_EQUAL(10, fetched.score);
    TEST_ASSERT_EQUAL(12, fetched.score_up);
    TEST_ASSERT_EQUAL(2, fetched.score_down);
    TEST_ASSERT_FALSE(fetched.is_seen);
    TEST_ASSERT_FALSE(fetched.is_favorited);

    bunny_db_post_free(&fetched);
}

void test_post_upsert_updates_existing_row(void)
{
    bunny_db_post_upsert_t post;
    make_test_post(&post, 222, 1);

    int64_t first_id = 0;
    bunny_db_post_upsert(g_db, &post, &first_id);

    post.score = 99;
    int64_t second_id = 0;
    bunny_db_result_t result = bunny_db_post_upsert(g_db, &post, &second_id);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_EQUAL(first_id, second_id);

    bunny_db_post_t fetched;
    bunny_db_post_get(g_db, BUNNY_DB_SITE_E621, 222, &fetched);
    TEST_ASSERT_EQUAL(99, fetched.score);
    bunny_db_post_free(&fetched);
}

void test_post_get_not_found(void)
{
    bunny_db_post_t fetched;
    bunny_db_result_t result = bunny_db_post_get(g_db, BUNNY_DB_SITE_E621, 999999, &fetched);
    TEST_ASSERT_EQUAL(BUNNY_DB_ERR_NOT_FOUND, result);
}

void test_seen_state(void)
{
    bunny_db_post_upsert_t post1;
    bunny_db_post_upsert_t post2;
    make_test_post(&post1, 301, 1);
    make_test_post(&post2, 302, 1);
    int64_t id1 = 0;
    int64_t id2 = 0;
    bunny_db_post_upsert(g_db, &post1, &id1);
    bunny_db_post_upsert(g_db, &post2, &id2);

    int64_t unseen = -1;
    bunny_db_count_unseen(g_db, &unseen);
    TEST_ASSERT_EQUAL(2, (int)unseen);

    bunny_db_result_t result = bunny_db_post_mark_seen(g_db, id1);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);

    bunny_db_count_unseen(g_db, &unseen);
    TEST_ASSERT_EQUAL(1, (int)unseen);

    bunny_db_post_t fetched;
    bunny_db_post_get(g_db, BUNNY_DB_SITE_E621, 301, &fetched);
    TEST_ASSERT_TRUE(fetched.is_seen);
    bunny_db_post_free(&fetched);

    bunny_db_post_get(g_db, BUNNY_DB_SITE_E621, 302, &fetched);
    TEST_ASSERT_FALSE(fetched.is_seen);
    bunny_db_post_free(&fetched);
}

void test_favorite_add_remove_list(void)
{
    bunny_db_post_upsert_t post;
    make_test_post(&post, 401, 1);
    int64_t id = 0;
    bunny_db_post_upsert(g_db, &post, &id);

    bunny_db_result_t result = bunny_db_favorite_add(g_db, id, 2);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);

    bunny_db_post_t fetched;
    bunny_db_post_get(g_db, BUNNY_DB_SITE_E621, 401, &fetched);
    TEST_ASSERT_TRUE(fetched.is_favorited);
    bunny_db_post_free(&fetched);

    bunny_db_post_list_t favorites;
    result = bunny_db_favorite_list(g_db, &favorites);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_EQUAL(1, (int)favorites.count);
    TEST_ASSERT_EQUAL(id, favorites.items[0].id);
    bunny_db_post_list_free(&favorites);

    result = bunny_db_favorite_remove(g_db, id);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);

    bunny_db_favorite_list(g_db, &favorites);
    TEST_ASSERT_EQUAL(0, (int)favorites.count);
    bunny_db_post_list_free(&favorites);
}

void test_vote_set_upserts_and_is_read_back(void)
{
    bunny_db_post_upsert_t post;
    make_test_post(&post, 410, 1);
    int64_t id = 0;
    bunny_db_post_upsert(g_db, &post, &id);

    bunny_db_post_t fetched;
    bunny_db_post_get(g_db, BUNNY_DB_SITE_E621, 410, &fetched);
    TEST_ASSERT_EQUAL(0, fetched.user_vote);
    bunny_db_post_free(&fetched);

    bunny_db_result_t result = bunny_db_vote_set(g_db, id, 1);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    bunny_db_post_get(g_db, BUNNY_DB_SITE_E621, 410, &fetched);
    TEST_ASSERT_EQUAL(1, fetched.user_vote);
    bunny_db_post_free(&fetched);

    /* Switching direction overwrites in place rather than erroring or
     * stacking a second row. */
    result = bunny_db_vote_set(g_db, id, -1);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    bunny_db_post_get(g_db, BUNNY_DB_SITE_E621, 410, &fetched);
    TEST_ASSERT_EQUAL(-1, fetched.user_vote);
    bunny_db_post_free(&fetched);
}

void test_vote_set_rejects_an_invalid_score(void)
{
    bunny_db_result_t result = bunny_db_vote_set(g_db, 1, 0);
    TEST_ASSERT_EQUAL(BUNNY_DB_ERR_INVALID_ARG, result);
}

void test_search_results_and_list_posts(void)
{
    int64_t search_id = 0;
    bunny_db_search_create(g_db, BUNNY_DB_SITE_E621, "wolves", "wolf", 24, NULL, &search_id);

    bunny_db_post_upsert_t post1;
    bunny_db_post_upsert_t post2;
    make_test_post(&post1, 501, 1);
    make_test_post(&post2, 502, 1);
    int64_t id1 = 0;
    int64_t id2 = 0;
    bunny_db_post_upsert(g_db, &post1, &id1);
    bunny_db_post_upsert(g_db, &post2, &id2);

    bunny_db_search_add_result(g_db, search_id, id1);
    bunny_db_search_add_result(g_db, search_id, id2);
    /* re-adding the same pair should be a no-op, not an error */
    bunny_db_result_t result = bunny_db_search_add_result(g_db, search_id, id1);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);

    bunny_db_post_list_t all_results;
    result = bunny_db_search_list_posts(g_db, search_id, false, &all_results);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_EQUAL(2, (int)all_results.count);
    bunny_db_post_list_free(&all_results);

    bunny_db_post_mark_seen(g_db, id1);

    bunny_db_post_list_t unseen_results;
    result = bunny_db_search_list_posts(g_db, search_id, true, &unseen_results);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_EQUAL(1, (int)unseen_results.count);
    TEST_ASSERT_EQUAL(id2, unseen_results.items[0].id);
    bunny_db_post_list_free(&unseen_results);
}

void test_search_list_posts_orders_newest_first_by_site_date(void)
{
    int64_t search_id = 0;
    bunny_db_search_create(g_db, BUNNY_DB_SITE_E621, "wolves", "wolf", 24, NULL, &search_id);

    /* Added to the search in the opposite order of their site creation
     * dates -- if list_posts still sorted by found_at (when this app linked
     * them to the search) rather than the site's own created_at_site, this
     * would come back oldest-first instead of newest-first. */
    bunny_db_post_upsert_t older_post;
    bunny_db_post_upsert_t newer_post;
    make_test_post(&older_post, 701, 1);
    make_test_post(&newer_post, 702, 1);
    older_post.created_at_site = "2026-01-01T00:00:00Z";
    newer_post.created_at_site = "2026-06-01T00:00:00Z";

    int64_t older_id = 0;
    int64_t newer_id = 0;
    bunny_db_post_upsert(g_db, &older_post, &older_id);
    bunny_db_search_add_result(g_db, search_id, older_id);
    bunny_db_post_upsert(g_db, &newer_post, &newer_id);
    bunny_db_search_add_result(g_db, search_id, newer_id);

    bunny_db_post_list_t results;
    bunny_db_result_t result = bunny_db_search_list_posts(g_db, search_id, false, &results);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_EQUAL(2, (int)results.count);
    TEST_ASSERT_EQUAL(newer_id, results.items[0].id);
    TEST_ASSERT_EQUAL(older_id, results.items[1].id);
    bunny_db_post_list_free(&results);
}

void test_search_mark_all_seen_only_affects_that_searchs_posts(void)
{
    int64_t search1_id = 0;
    int64_t search2_id = 0;
    bunny_db_search_create(g_db, BUNNY_DB_SITE_E621, "wolves", "wolf", 24, NULL, &search1_id);
    bunny_db_search_create(g_db, BUNNY_DB_SITE_E621, "foxes", "fox", 24, NULL, &search2_id);

    bunny_db_post_upsert_t post1;
    bunny_db_post_upsert_t post2;
    bunny_db_post_upsert_t post3;
    make_test_post(&post1, 921, 1);
    make_test_post(&post2, 922, 1);
    make_test_post(&post3, 923, 1);
    int64_t post1_id = 0;
    int64_t post2_id = 0;
    int64_t post3_id = 0;
    bunny_db_post_upsert(g_db, &post1, &post1_id);
    bunny_db_post_upsert(g_db, &post2, &post2_id);
    bunny_db_post_upsert(g_db, &post3, &post3_id);

    bunny_db_search_add_result(g_db, search1_id, post1_id);
    bunny_db_search_add_result(g_db, search1_id, post2_id);
    bunny_db_search_add_result(g_db, search2_id, post3_id);

    bunny_db_result_t result = bunny_db_search_mark_all_seen(g_db, search1_id);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);

    bunny_db_post_t fetched1;
    bunny_db_post_t fetched2;
    bunny_db_post_t fetched3;
    bunny_db_post_get_by_id(g_db, post1_id, &fetched1);
    bunny_db_post_get_by_id(g_db, post2_id, &fetched2);
    bunny_db_post_get_by_id(g_db, post3_id, &fetched3);
    TEST_ASSERT_TRUE(fetched1.is_seen);
    TEST_ASSERT_TRUE(fetched2.is_seen);
    TEST_ASSERT_FALSE(fetched3.is_seen);
    bunny_db_post_free(&fetched1);
    bunny_db_post_free(&fetched2);
    bunny_db_post_free(&fetched3);
}

void test_download_record_and_list(void)
{
    bunny_db_post_upsert_t post;
    make_test_post(&post, 601, 1);
    int64_t id = 0;
    bunny_db_post_upsert(g_db, &post, &id);

    int64_t download_id = 0;
    bunny_db_result_t result = bunny_db_download_record(g_db, id, "/downloads/someartist/601.jpg", "abc123", true, &download_id);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_TRUE(download_id > 0);

    bunny_db_download_list_t downloads;
    result = bunny_db_download_list_for_post(g_db, id, &downloads);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_EQUAL(1, (int)downloads.count);
    TEST_ASSERT_EQUAL_STRING("/downloads/someartist/601.jpg", downloads.items[0].file_path);
    TEST_ASSERT_EQUAL_STRING("abc123", downloads.items[0].checksum_md5);
    TEST_ASSERT_TRUE(downloads.items[0].checksum_verified);
    bunny_db_download_list_free(&downloads);
}

void test_post_get_by_id(void)
{
    bunny_db_post_upsert_t post;
    make_test_post(&post, 901, 1);
    int64_t id = 0;
    bunny_db_post_upsert(g_db, &post, &id);

    bunny_db_post_t fetched;
    bunny_db_result_t result = bunny_db_post_get_by_id(g_db, id, &fetched);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_EQUAL(901, fetched.external_id);
    TEST_ASSERT_EQUAL_STRING("someartist", fetched.artist);
    bunny_db_post_free(&fetched);
}

void test_post_get_by_id_not_found(void)
{
    bunny_db_post_t fetched;
    bunny_db_result_t result = bunny_db_post_get_by_id(g_db, 999999, &fetched);
    TEST_ASSERT_EQUAL(BUNNY_DB_ERR_NOT_FOUND, result);
}

void test_action_queue_add_and_list_pending(void)
{
    bunny_db_post_upsert_t post;
    make_test_post(&post, 1001, 1);
    int64_t post_id = 0;
    bunny_db_post_upsert(g_db, &post, &post_id);

    int64_t action_id = 0;
    bunny_db_result_t result = bunny_db_action_queue_add(g_db, post_id, BUNNY_DB_ACTION_VOTE, "{\"score\":1}", &action_id);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_TRUE(action_id > 0);

    bunny_db_action_list_t pending;
    result = bunny_db_action_queue_list_pending(g_db, &pending);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_EQUAL(1, (int)pending.count);
    TEST_ASSERT_EQUAL(action_id, pending.items[0].id);
    TEST_ASSERT_EQUAL(post_id, pending.items[0].post_id);
    TEST_ASSERT_EQUAL(BUNNY_DB_ACTION_VOTE, pending.items[0].action_type);
    TEST_ASSERT_EQUAL_STRING("{\"score\":1}", pending.items[0].payload);
    TEST_ASSERT_EQUAL(BUNNY_DB_ACTION_STATUS_PENDING, pending.items[0].status);
    TEST_ASSERT_NULL(pending.items[0].attempted_at);
    bunny_db_action_list_free(&pending);
}

void test_action_queue_mark_done_removes_from_pending(void)
{
    bunny_db_post_upsert_t post;
    make_test_post(&post, 1002, 1);
    int64_t post_id = 0;
    bunny_db_post_upsert(g_db, &post, &post_id);

    int64_t action_id = 0;
    bunny_db_action_queue_add(g_db, post_id, BUNNY_DB_ACTION_FAVORITE_ADD, NULL, &action_id);

    bunny_db_result_t result = bunny_db_action_queue_mark_done(g_db, action_id);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);

    bunny_db_action_list_t pending;
    bunny_db_action_queue_list_pending(g_db, &pending);
    TEST_ASSERT_EQUAL(0, (int)pending.count);
    bunny_db_action_list_free(&pending);
}

void test_action_queue_mark_failed_records_error(void)
{
    bunny_db_post_upsert_t post;
    make_test_post(&post, 1003, 1);
    int64_t post_id = 0;
    bunny_db_post_upsert(g_db, &post, &post_id);

    int64_t action_id = 0;
    bunny_db_action_queue_add(g_db, post_id, BUNNY_DB_ACTION_COMMENT, NULL, &action_id);

    bunny_db_result_t result = bunny_db_action_queue_mark_failed(g_db, action_id, "network error");
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);

    bunny_db_action_list_t pending;
    bunny_db_action_queue_list_pending(g_db, &pending);
    TEST_ASSERT_EQUAL(0, (int)pending.count); /* failed rows aren't pending anymore */
    bunny_db_action_list_free(&pending);
}

void test_top_favorited_tags(void)
{
    const char *tags1[] = {"wolf", "forest"};
    const char *tags2[] = {"wolf", "meadow"};

    bunny_db_post_upsert_t post1;
    bunny_db_post_upsert_t post2;
    make_test_post(&post1, 701, 1);
    make_test_post(&post2, 702, 1);
    post1.tags = tags1;
    post1.tag_count = 2;
    post2.tags = tags2;
    post2.tag_count = 2;

    int64_t id1 = 0;
    int64_t id2 = 0;
    bunny_db_post_upsert(g_db, &post1, &id1);
    bunny_db_post_upsert(g_db, &post2, &id2);

    bunny_db_favorite_add(g_db, id1, -1);
    bunny_db_favorite_add(g_db, id2, -1);

    bunny_db_tag_stat_list_t stats;
    bunny_db_result_t result = bunny_db_top_favorited_tags(g_db, 10, &stats);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_EQUAL(3, (int)stats.count); /* wolf, forest, meadow */
    TEST_ASSERT_EQUAL_STRING("wolf", stats.items[0].name);
    TEST_ASSERT_EQUAL(2, stats.items[0].count);

    bunny_db_tag_stat_list_free(&stats);
}

void test_tag_autocomplete_prefix_match(void)
{
    const char *tags1[] = {"wolf"};
    const char *tags2[] = {"wolfhound"};
    const char *tags3[] = {"cat"};

    bunny_db_post_upsert_t post1;
    bunny_db_post_upsert_t post2;
    bunny_db_post_upsert_t post3;
    make_test_post(&post1, 801, 1);
    make_test_post(&post2, 802, 1);
    make_test_post(&post3, 803, 1);
    post1.tags = tags1;
    post1.tag_count = 1;
    post2.tags = tags2;
    post2.tag_count = 1;
    post3.tags = tags3;
    post3.tag_count = 1;
    bunny_db_post_upsert(g_db, &post1, NULL);
    bunny_db_post_upsert(g_db, &post2, NULL);
    bunny_db_post_upsert(g_db, &post3, NULL);

    bunny_db_tag_stat_list_t results;
    bunny_db_result_t result = bunny_db_tag_autocomplete(g_db, BUNNY_DB_SITE_E621, "wolf", 10, &results);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_EQUAL(2, (int)results.count);
    bunny_db_tag_stat_list_free(&results);
}

void test_tag_autocomplete_orders_by_usage_then_name(void)
{
    const char *tags_a[] = {"aardvark"};
    const char *tags_b[] = {"antelope"};

    bunny_db_post_upsert_t post1;
    bunny_db_post_upsert_t post2;
    bunny_db_post_upsert_t post3;
    make_test_post(&post1, 811, 1);
    make_test_post(&post2, 812, 1);
    make_test_post(&post3, 813, 1);
    post1.tags = tags_a;
    post1.tag_count = 1;
    post2.tags = tags_b;
    post2.tag_count = 1;
    post3.tags = tags_b;
    post3.tag_count = 1;
    bunny_db_post_upsert(g_db, &post1, NULL); /* aardvark: 1 post */
    bunny_db_post_upsert(g_db, &post2, NULL); /* antelope: 2 posts */
    bunny_db_post_upsert(g_db, &post3, NULL);

    bunny_db_tag_stat_list_t results;
    bunny_db_result_t result = bunny_db_tag_autocomplete(g_db, BUNNY_DB_SITE_E621, "a", 10, &results);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_EQUAL(2, (int)results.count);
    TEST_ASSERT_EQUAL_STRING("antelope", results.items[0].name); /* more posts wins, despite sorting after "aardvark" alphabetically */
    TEST_ASSERT_EQUAL(2, results.items[0].count);
    TEST_ASSERT_EQUAL_STRING("aardvark", results.items[1].name);
    bunny_db_tag_stat_list_free(&results);
}

void test_tag_autocomplete_is_per_site(void)
{
    const char *tags[] = {"shared_tag_name"};

    bunny_db_post_upsert_t post1;
    bunny_db_post_upsert_t post2;
    make_test_post(&post1, 821, 1);
    make_test_post(&post2, 822, 1);
    post1.tags = tags;
    post1.tag_count = 1;
    post2.site = BUNNY_DB_SITE_INKBUNNY;
    post2.tags = tags;
    post2.tag_count = 1;
    bunny_db_post_upsert(g_db, &post1, NULL);
    bunny_db_post_upsert(g_db, &post2, NULL);

    bunny_db_tag_stat_list_t e621_results;
    bunny_db_tag_autocomplete(g_db, BUNNY_DB_SITE_E621, "shared", 10, &e621_results);
    TEST_ASSERT_EQUAL(1, (int)e621_results.count);
    bunny_db_tag_stat_list_free(&e621_results);

    bunny_db_tag_stat_list_t inkbunny_results;
    bunny_db_tag_autocomplete(g_db, BUNNY_DB_SITE_INKBUNNY, "shared", 10, &inkbunny_results);
    TEST_ASSERT_EQUAL(1, (int)inkbunny_results.count);
    bunny_db_tag_stat_list_free(&inkbunny_results);
}

void test_tag_autocomplete_escapes_literal_underscore(void)
{
    /* "_" is a SQL LIKE wildcard for "any single character" -- a literal
     * underscore in the prefix must not match unrelated tags like
     * "digitalXmedia" the way an unescaped LIKE pattern would. */
    const char *tags1[] = {"digital_media"};
    const char *tags2[] = {"digitalXmedia"};

    bunny_db_post_upsert_t post1;
    bunny_db_post_upsert_t post2;
    make_test_post(&post1, 831, 1);
    make_test_post(&post2, 832, 1);
    post1.tags = tags1;
    post1.tag_count = 1;
    post2.tags = tags2;
    post2.tag_count = 1;
    bunny_db_post_upsert(g_db, &post1, NULL);
    bunny_db_post_upsert(g_db, &post2, NULL);

    bunny_db_tag_stat_list_t results;
    bunny_db_result_t result = bunny_db_tag_autocomplete(g_db, BUNNY_DB_SITE_E621, "digital_", 10, &results);
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, result);
    TEST_ASSERT_EQUAL(1, (int)results.count);
    TEST_ASSERT_EQUAL_STRING("digital_media", results.items[0].name);
    bunny_db_tag_stat_list_free(&results);
}

void test_migrations_apply_cleanly_and_are_idempotent_on_reopen(void)
{
    /* setUp's :memory: db already proves migrations apply to a fresh
     * database (every other test in this file exercises that implicitly).
     * This test needs a real file to prove reopening an *already-migrated*
     * database doesn't fail or re-apply the ALTER TABLEs. */
    const char *path = "/tmp/bunny_db_test_migration_idempotent.sqlite3";
    remove(path);

    bunny_db_t *db1 = NULL;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_open(path, &db1));
    bunny_db_close(db1);

    bunny_db_t *db2 = NULL;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_open(path, &db2));

    bunny_db_post_upsert_t post;
    make_test_post(&post, 9001, 7);
    int64_t post_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(db2, &post, &post_id));

    bunny_db_post_t fetched;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_get_by_id(db2, post_id, &fetched));
    TEST_ASSERT_EQUAL(9, fetched.score_up);
    TEST_ASSERT_EQUAL(2, fetched.score_down);
    bunny_db_post_free(&fetched);

    bunny_db_close(db2);
    remove(path);
}

void test_post_get_tags_by_category(void)
{
    const char *tags[] = {"forest", "wolf", "some_artist"};
    const char *categories[] = {"general", "species", "artist"};
    bunny_db_post_upsert_t post;
    make_test_post(&post, 601, 1);
    post.tags = tags;
    post.tag_count = 3;
    post.tag_categories = categories;

    int64_t post_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(g_db, &post, &post_id));

    bunny_db_post_tag_list_t list;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_get_tags_by_category(g_db, post_id, &list));
    TEST_ASSERT_EQUAL(3, list.count);

    for (size_t i = 0; i < list.count; i++) {
        if (strcmp(list.items[i].name, "forest") == 0) {
            TEST_ASSERT_EQUAL_STRING("general", list.items[i].category);
        } else if (strcmp(list.items[i].name, "wolf") == 0) {
            TEST_ASSERT_EQUAL_STRING("species", list.items[i].category);
        } else if (strcmp(list.items[i].name, "some_artist") == 0) {
            TEST_ASSERT_EQUAL_STRING("artist", list.items[i].category);
        } else {
            TEST_FAIL_MESSAGE("unexpected tag name");
        }
    }

    bunny_db_post_tag_list_free(&list);
}

void test_post_get_tags_by_category_uncategorized_when_no_category_given(void)
{
    const char *tags[] = {"some_keyword"};
    bunny_db_post_upsert_t post;
    make_test_post(&post, 602, 1);
    post.tags = tags;
    post.tag_count = 1;
    post.tag_categories = NULL; /* Inkbunny-style: no category info at all */

    int64_t post_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(g_db, &post, &post_id));

    bunny_db_post_tag_list_t list;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_get_tags_by_category(g_db, post_id, &list));
    TEST_ASSERT_EQUAL(1, list.count);
    TEST_ASSERT_EQUAL_STRING("some_keyword", list.items[0].name);
    TEST_ASSERT_NULL(list.items[0].category);

    bunny_db_post_tag_list_free(&list);
}

void test_post_get_tags_by_category_tag_category_is_shared_across_posts(void)
{
    /* A tag's category is a property of the tag itself (see schema.h), not
     * a given post -- upserting it again for a different post referencing
     * the same tag name should not require re-specifying the category. */
    const char *tags1[] = {"shared_tag"};
    const char *categories1[] = {"meta"};
    bunny_db_post_upsert_t post1;
    make_test_post(&post1, 603, 1);
    post1.tags = tags1;
    post1.tag_count = 1;
    post1.tag_categories = categories1;
    int64_t post1_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(g_db, &post1, &post1_id));

    const char *tags2[] = {"shared_tag"};
    bunny_db_post_upsert_t post2;
    make_test_post(&post2, 604, 1);
    post2.tags = tags2;
    post2.tag_count = 1;
    post2.tag_categories = NULL;
    int64_t post2_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(g_db, &post2, &post2_id));

    bunny_db_post_tag_list_t list;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_get_tags_by_category(g_db, post2_id, &list));
    TEST_ASSERT_EQUAL(1, list.count);
    TEST_ASSERT_EQUAL_STRING("meta", list.items[0].category);

    bunny_db_post_tag_list_free(&list);
}

void test_post_get_sources_preserves_order(void)
{
    const char *sources[] = {"https://example.com/a", "https://example.com/b", "https://example.com/c"};
    bunny_db_post_upsert_t post;
    make_test_post(&post, 605, 1);
    post.sources = sources;
    post.source_count = 3;

    int64_t post_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(g_db, &post, &post_id));

    bunny_db_string_list_t list;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_get_sources(g_db, post_id, &list));
    TEST_ASSERT_EQUAL(3, list.count);
    TEST_ASSERT_EQUAL_STRING("https://example.com/a", list.items[0]);
    TEST_ASSERT_EQUAL_STRING("https://example.com/b", list.items[1]);
    TEST_ASSERT_EQUAL_STRING("https://example.com/c", list.items[2]);

    bunny_db_string_list_free(&list);
}

void test_post_get_sources_empty_when_none_given(void)
{
    bunny_db_post_upsert_t post;
    make_test_post(&post, 606, 1);
    /* sources/source_count left at their memset-zero defaults (NULL/0) --
     * the Inkbunny case, which has no source field at all. */

    int64_t post_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(g_db, &post, &post_id));

    bunny_db_string_list_t list;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_get_sources(g_db, post_id, &list));
    TEST_ASSERT_EQUAL(0, list.count);

    bunny_db_string_list_free(&list);
}

void test_post_upsert_replaces_sources_wholesale_on_resync(void)
{
    const char *sources1[] = {"https://example.com/old"};
    bunny_db_post_upsert_t post;
    make_test_post(&post, 607, 1);
    post.sources = sources1;
    post.source_count = 1;

    int64_t post_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(g_db, &post, &post_id));

    const char *sources2[] = {"https://example.com/new1", "https://example.com/new2"};
    post.sources = sources2;
    post.source_count = 2;
    int64_t second_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(g_db, &post, &second_id));
    TEST_ASSERT_EQUAL(post_id, second_id);

    bunny_db_string_list_t list;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_get_sources(g_db, post_id, &list));
    TEST_ASSERT_EQUAL(2, list.count);
    TEST_ASSERT_EQUAL_STRING("https://example.com/new1", list.items[0]);
    TEST_ASSERT_EQUAL_STRING("https://example.com/new2", list.items[1]);

    bunny_db_string_list_free(&list);
}

void test_post_get_relationships_defaults_when_no_row(void)
{
    bunny_db_post_upsert_t post;
    make_test_post(&post, 608, 1);
    /* has_parent/has_active_children/child_external_ids left at their
     * memset-zero defaults -- a post with no relationships at all. */

    int64_t post_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(g_db, &post, &post_id));

    bunny_db_post_relationships_t relationships;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_get_relationships(g_db, post_id, &relationships));
    TEST_ASSERT_FALSE(relationships.has_parent);
    TEST_ASSERT_FALSE(relationships.has_active_children);
    TEST_ASSERT_EQUAL(0, relationships.children.count);

    bunny_db_post_relationships_free(&relationships);
}

void test_post_get_relationships_with_parent_and_children(void)
{
    int64_t children[] = {101, 102};
    bunny_db_post_upsert_t post;
    make_test_post(&post, 609, 1);
    post.has_parent = true;
    post.parent_external_id = 999;
    post.has_active_children = true;
    post.child_external_ids = children;
    post.child_count = 2;

    int64_t post_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(g_db, &post, &post_id));

    bunny_db_post_relationships_t relationships;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_get_relationships(g_db, post_id, &relationships));
    TEST_ASSERT_TRUE(relationships.has_parent);
    TEST_ASSERT_EQUAL(999, relationships.parent_external_id);
    TEST_ASSERT_TRUE(relationships.has_active_children);
    TEST_ASSERT_EQUAL(2, relationships.children.count);
    TEST_ASSERT_EQUAL(101, relationships.children.items[0]);
    TEST_ASSERT_EQUAL(102, relationships.children.items[1]);

    bunny_db_post_relationships_free(&relationships);
}

void test_post_upsert_replaces_relationships_wholesale_on_resync(void)
{
    int64_t children1[] = {101};
    bunny_db_post_upsert_t post;
    make_test_post(&post, 610, 1);
    post.has_parent = true;
    post.parent_external_id = 999;
    post.child_external_ids = children1;
    post.child_count = 1;

    int64_t post_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(g_db, &post, &post_id));

    /* Re-sync with the parent gone and a different child set -- the stale
     * parent_external_id/children must not linger. */
    post.has_parent = false;
    int64_t children2[] = {201, 202};
    post.child_external_ids = children2;
    post.child_count = 2;
    int64_t second_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(g_db, &post, &second_id));
    TEST_ASSERT_EQUAL(post_id, second_id);

    bunny_db_post_relationships_t relationships;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_get_relationships(g_db, post_id, &relationships));
    TEST_ASSERT_FALSE(relationships.has_parent);
    TEST_ASSERT_EQUAL(2, relationships.children.count);
    TEST_ASSERT_EQUAL(201, relationships.children.items[0]);
    TEST_ASSERT_EQUAL(202, relationships.children.items[1]);

    bunny_db_post_relationships_free(&relationships);
}

void test_post_get_pool_ids_empty_when_none(void)
{
    bunny_db_post_upsert_t post;
    make_test_post(&post, 611, 1);

    int64_t post_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(g_db, &post, &post_id));

    bunny_db_int64_list_t pools;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_get_pool_ids(g_db, post_id, &pools));
    TEST_ASSERT_EQUAL(0, pools.count);

    bunny_db_int64_list_free(&pools);
}

void test_post_get_pool_ids_returns_pools(void)
{
    int64_t pool_ids[] = {5, 9};
    bunny_db_post_upsert_t post;
    make_test_post(&post, 612, 1);
    post.pool_ids = pool_ids;
    post.pool_count = 2;

    int64_t post_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(g_db, &post, &post_id));

    bunny_db_int64_list_t pools;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_get_pool_ids(g_db, post_id, &pools));
    TEST_ASSERT_EQUAL(2, pools.count);
    TEST_ASSERT_EQUAL(5, pools.items[0]);
    TEST_ASSERT_EQUAL(9, pools.items[1]);

    bunny_db_int64_list_free(&pools);
}

void test_post_sample_url_round_trips_and_is_nullable(void)
{
    bunny_db_post_upsert_t post;
    make_test_post(&post, 613, 1);
    post.sample_url = "https://example.com/sample.jpg";

    int64_t post_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(g_db, &post, &post_id));

    bunny_db_post_t fetched;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_get_by_id(g_db, post_id, &fetched));
    TEST_ASSERT_EQUAL_STRING("https://example.com/sample.jpg", fetched.sample_url);
    bunny_db_post_free(&fetched);

    /* A post with no sample_url given at all (the memset-zero default, e.g.
     * Inkbunny submissions with no "screen" file variant) should come back
     * NULL, not an empty string or an error. */
    bunny_db_post_upsert_t post_no_sample;
    make_test_post(&post_no_sample, 614, 1);

    int64_t no_sample_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(g_db, &post_no_sample, &no_sample_id));

    bunny_db_post_t fetched_no_sample;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_get_by_id(g_db, no_sample_id, &fetched_no_sample));
    TEST_ASSERT_NULL(fetched_no_sample.sample_url);
    bunny_db_post_free(&fetched_no_sample);
}

void test_post_upsert_replaces_sample_url_wholesale_on_resync(void)
{
    bunny_db_post_upsert_t post;
    make_test_post(&post, 615, 1);
    post.sample_url = "https://example.com/old_sample.jpg";

    int64_t post_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(g_db, &post, &post_id));

    /* Re-sync with the sample URL gone -- the stale value must not linger. */
    post.sample_url = NULL;
    int64_t second_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_upsert(g_db, &post, &second_id));
    TEST_ASSERT_EQUAL(post_id, second_id);

    bunny_db_post_t fetched;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_post_get_by_id(g_db, post_id, &fetched));
    TEST_ASSERT_NULL(fetched.sample_url);
    bunny_db_post_free(&fetched);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_open_close);
    RUN_TEST(test_account_set_and_get);
    RUN_TEST(test_account_set_upserts_by_site);
    RUN_TEST(test_account_get_not_found);
    RUN_TEST(test_account_delete);
    RUN_TEST(test_account_is_per_site);
    RUN_TEST(test_search_create_and_list);
    RUN_TEST(test_search_create_with_auto_favorite);
    RUN_TEST(test_search_create_defaults_auto_favorite_stars_to_one);
    RUN_TEST(test_search_update_modifies_label_query_interval_and_options);
    RUN_TEST(test_search_list_unseen_count);
    RUN_TEST(test_search_default_interval);
    RUN_TEST(test_search_delete);
    RUN_TEST(test_search_touch_last_run);
    RUN_TEST(test_post_upsert_and_get);
    RUN_TEST(test_post_upsert_updates_existing_row);
    RUN_TEST(test_post_get_not_found);
    RUN_TEST(test_seen_state);
    RUN_TEST(test_search_mark_all_seen_only_affects_that_searchs_posts);
    RUN_TEST(test_favorite_add_remove_list);
    RUN_TEST(test_vote_set_upserts_and_is_read_back);
    RUN_TEST(test_vote_set_rejects_an_invalid_score);
    RUN_TEST(test_search_results_and_list_posts);
    RUN_TEST(test_search_list_posts_orders_newest_first_by_site_date);
    RUN_TEST(test_download_record_and_list);
    RUN_TEST(test_post_get_by_id);
    RUN_TEST(test_post_get_by_id_not_found);
    RUN_TEST(test_action_queue_add_and_list_pending);
    RUN_TEST(test_action_queue_mark_done_removes_from_pending);
    RUN_TEST(test_action_queue_mark_failed_records_error);
    RUN_TEST(test_top_favorited_tags);
    RUN_TEST(test_tag_autocomplete_prefix_match);
    RUN_TEST(test_tag_autocomplete_orders_by_usage_then_name);
    RUN_TEST(test_tag_autocomplete_is_per_site);
    RUN_TEST(test_tag_autocomplete_escapes_literal_underscore);
    RUN_TEST(test_migrations_apply_cleanly_and_are_idempotent_on_reopen);
    RUN_TEST(test_post_get_tags_by_category);
    RUN_TEST(test_post_get_tags_by_category_uncategorized_when_no_category_given);
    RUN_TEST(test_post_get_tags_by_category_tag_category_is_shared_across_posts);
    RUN_TEST(test_post_get_sources_preserves_order);
    RUN_TEST(test_post_get_sources_empty_when_none_given);
    RUN_TEST(test_post_upsert_replaces_sources_wholesale_on_resync);
    RUN_TEST(test_post_get_relationships_defaults_when_no_row);
    RUN_TEST(test_post_get_relationships_with_parent_and_children);
    RUN_TEST(test_post_upsert_replaces_relationships_wholesale_on_resync);
    RUN_TEST(test_post_get_pool_ids_empty_when_none);
    RUN_TEST(test_post_get_pool_ids_returns_pools);
    RUN_TEST(test_post_sample_url_round_trips_and_is_nullable);
    RUN_TEST(test_post_upsert_replaces_sample_url_wholesale_on_resync);
    return UNITY_END();
}
