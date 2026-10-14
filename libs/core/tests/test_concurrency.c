#include "unity.h"

#include <pthread.h>
#include <stdatomic.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "bunny_core/core.h"

/* test_pure_db_call_does_not_block_on_concurrent_slow_sync pins down the
 * POST-FIX invariant (bunny_core's own db_mutex never blocks a pure-db call
 * behind a network call) -- it would NOT have caught the original production
 * bug, which lived entirely in the server's now-deleted
 * server_context_t.core_mutex (server/src/context.h), wrapping whole
 * bunny_core_sync_search calls including their network I/O. That regression
 * is instead covered by a real multi-threaded-client test in
 * server/tests/test_integration.c.
 *
 * test_two_concurrent_syncs_are_serialized pins down the newer sync_mutex
 * invariant (see internal.h): two site-facing syncs of DIFFERENT searches
 * must never run concurrently, so the server never has more than one
 * sync/queue-processing operation talking to e621/Inkbunny at once.
 *
 * Both tests exercise bunny_core directly, with no server layer at all. */

static bunny_core_t *g_core;
static bunny_http_transport_t g_e621_transport;
static atomic_bool g_sync_done;

/* Sleeps before returning an empty page -- the slow network call this test
 * exists to simulate. A single empty page is enough: sync_e621_search's
 * first-scan loop does exactly one e621_search_posts call, sees count == 0
 * (< BUNNY_CORE_SYNC_E621_PAGE_LIMIT), and returns -- so one artificially
 * slow response holds up the whole sync_search call for the sleep's
 * duration. */
static bunny_http_result_t slow_empty_page_send(void *user_data, const bunny_http_request_t *request, bunny_http_response_t *out_response)
{
    (void)user_data;
    (void)request;
    usleep(300000); /* 300ms -- the "blocking network call" this test proves doesn't block a concurrent db read */
    const char *body = "{\"posts\":[]}";
    out_response->status = 200;
    out_response->body = strdup(body);
    out_response->body_len = strlen(body);
    return BUNNY_HTTP_OK;
}

void setUp(void)
{
    atomic_init(&g_sync_done, false);
    g_e621_transport.send = slow_empty_page_send;
    g_e621_transport.user_data = NULL;

    bunny_core_config_t config;
    memset(&config, 0, sizeof(config));
    config.db_path = ":memory:";
    config.user_agent = "bunny-tests/1.0 (concurrency)";
    config.e621_transport = &g_e621_transport;
    config.min_request_interval_sec = 0.0;

    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, bunny_core_open(&config, &g_core));

    int64_t search_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, bunny_core_search_create(g_core, BUNNY_DB_SITE_E621, "slow", "test_query", 24, NULL, &search_id));
}

void tearDown(void)
{
    bunny_core_close(g_core);
    g_core = NULL;
}

static void *run_slow_sync(void *arg)
{
    int64_t search_id = *(int64_t *)arg;
    bunny_core_sync_stats_t stats;
    bunny_core_sync_search(g_core, search_id, &stats);
    atomic_store(&g_sync_done, true);
    return NULL;
}

static double elapsed_ms(struct timespec start)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (now.tv_sec - start.tv_sec) * 1000.0 + (now.tv_nsec - start.tv_nsec) / 1e6;
}

void test_pure_db_call_does_not_block_on_concurrent_slow_sync(void)
{
    bunny_db_search_list_t list;
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, bunny_core_search_list(g_core, &list));
    TEST_ASSERT_TRUE(list.count >= 1);
    int64_t search_id = list.items[0].id;
    bunny_db_search_list_free(&list);

    pthread_t sync_thread;
    struct timespec start;
    clock_gettime(CLOCK_MONOTONIC, &start);
    TEST_ASSERT_EQUAL(0, pthread_create(&sync_thread, NULL, run_slow_sync, &search_id));

    /* Give the sync thread a moment to actually be inside the slow network
     * call before racing the fast call against it. */
    usleep(50000); /* 50ms */
    TEST_ASSERT_FALSE(atomic_load(&g_sync_done)); /* sanity: sync is still in flight (300ms sleep > 50ms headstart) */

    bunny_db_search_list_t fast_result;
    bunny_core_result_t fast_status = bunny_core_search_list(g_core, &fast_result);
    double fast_elapsed = elapsed_ms(start);

    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, fast_status);
    bunny_db_search_list_free(&fast_result);

    /* The core assertion: the fast pure-db call returned well before the
     * slow sync's 300ms network sleep could have finished -- proving the
     * network call did NOT hold any lock that would have serialized this
     * read behind it. Threshold set well under 300ms with margin for
     * scheduling jitter, well above what a single bunny_db_search_list call
     * should ever take. */
    TEST_ASSERT_TRUE_MESSAGE(fast_elapsed < 150.0, "fast db read was blocked by the concurrent slow sync's network call");

    pthread_join(sync_thread, NULL);
    TEST_ASSERT_TRUE(atomic_load(&g_sync_done));
}

void test_two_concurrent_syncs_are_serialized(void)
{
    int64_t second_search_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, bunny_core_search_create(g_core, BUNNY_DB_SITE_E621, "slow2", "test_query2", 24, NULL, &second_search_id));

    bunny_db_search_list_t list;
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, bunny_core_search_list(g_core, &list));
    int64_t first_search_id = -1;
    for (size_t i = 0; i < list.count; i++) {
        if (list.items[i].id != second_search_id) {
            first_search_id = list.items[i].id;
            break;
        }
    }
    bunny_db_search_list_free(&list);
    TEST_ASSERT_TRUE(first_search_id >= 0);

    struct timespec start;
    clock_gettime(CLOCK_MONOTONIC, &start);

    pthread_t first_thread;
    TEST_ASSERT_EQUAL(0, pthread_create(&first_thread, NULL, run_slow_sync, &first_search_id));
    usleep(50000); /* 50ms head start, same reasoning as the other test */

    bunny_core_sync_stats_t second_stats;
    bunny_core_result_t second_status = bunny_core_sync_search(g_core, second_search_id, &second_stats);
    double second_elapsed = elapsed_ms(start);

    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, second_status);
    /* sync_mutex serializes the two syncs -- the second one can't even start
     * its own 300ms sleep until the first (which got a 50ms head start)
     * releases the lock, so the second call alone should take close to
     * another full 300ms on top of that head start. Threshold set well
     * below the ~550ms expected total but well above what any unserialized
     * (parallel) execution could produce (would finish near the 50ms mark). */
    TEST_ASSERT_TRUE_MESSAGE(second_elapsed > 250.0, "second sync returned too fast -- syncs are not being serialized");

    pthread_join(first_thread, NULL);
    TEST_ASSERT_TRUE(atomic_load(&g_sync_done));
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_pure_db_call_does_not_block_on_concurrent_slow_sync);
    RUN_TEST(test_two_concurrent_syncs_are_serialized);
    return UNITY_END();
}
