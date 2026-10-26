#include "unity.h"

#include <bunny_core/core.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "auth.h"
#include "config.h"
#include "health_check.h"
#include "tls.h"

static char g_data_dir[64];

void setUp(void)
{
    /* mkdtemp mutates its argument in place (replaces XXXXXX with the real
     * name), so the template has to be re-copied in before every test --
     * reusing the same buffer across setUp calls without resetting it would
     * mean only the first test's mkdtemp call ever actually matches the
     * required XXXXXX pattern. */
    strcpy(g_data_dir, "/tmp/bunny_health_check_test_XXXXXX");
    TEST_ASSERT_NOT_NULL(mkdtemp(g_data_dir));
}

static void remove_in_data_dir(const char *name)
{
    char path[600];
    snprintf(path, sizeof(path), "%s/%s", g_data_dir, name);
    remove(path);
}

void tearDown(void)
{
    remove_in_data_dir("auth_token");
    remove_in_data_dir("server.pem");
    remove_in_data_dir("bunny.db");
    remove_in_data_dir("bunny.db-wal");
    remove_in_data_dir("bunny.db-shm");
    rmdir(g_data_dir);
}

/* Builds valid auth_token/server.pem/bunny.db via the same real functions
 * the actual server uses (not hand-crafted fixtures), so these tests reuse
 * production code to establish the "healthy" baseline. */
static void seed_valid_data_dir(void)
{
    server_auth_t *auth = server_auth_load(g_data_dir);
    TEST_ASSERT_NOT_NULL(auth);
    server_auth_free(auth);

    char *cert_path = server_tls_ensure_cert(g_data_dir);
    TEST_ASSERT_NOT_NULL(cert_path);
    free(cert_path);

    char db_path[600];
    snprintf(db_path, sizeof(db_path), "%s/bunny.db", g_data_dir);
    bunny_core_config_t core_config;
    memset(&core_config, 0, sizeof(core_config));
    core_config.db_path = db_path;
    core_config.user_agent = "bunny-tests/1.0";
    bunny_core_t *core = NULL;
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, bunny_core_open(&core_config, &core));
    bunny_core_close(core);
}

static server_config_t make_config(void)
{
    server_config_t config;
    config.port = 8443;
    config.data_dir = g_data_dir;
    config.user_agent = "bunny-tests/1.0";
    config.poll_interval_sec = 900;
    return config;
}

void test_health_check_passes_on_a_fully_valid_data_dir(void)
{
    seed_valid_data_dir();
    server_config_t config = make_config();
    TEST_ASSERT_TRUE(server_run_health_check(&config));
}

void test_health_check_fails_when_database_is_missing(void)
{
    server_auth_t *auth = server_auth_load(g_data_dir);
    TEST_ASSERT_NOT_NULL(auth);
    server_auth_free(auth);
    char *cert_path = server_tls_ensure_cert(g_data_dir);
    TEST_ASSERT_NOT_NULL(cert_path);
    free(cert_path);
    /* bunny.db deliberately never created. */

    server_config_t config = make_config();
    TEST_ASSERT_FALSE(server_run_health_check(&config));
}

void test_health_check_fails_when_auth_token_is_missing(void)
{
    seed_valid_data_dir();
    remove_in_data_dir("auth_token");

    server_config_t config = make_config();
    TEST_ASSERT_FALSE(server_run_health_check(&config));
}

void test_health_check_fails_when_cert_is_missing(void)
{
    seed_valid_data_dir();
    remove_in_data_dir("server.pem");

    server_config_t config = make_config();
    TEST_ASSERT_FALSE(server_run_health_check(&config));
}

void test_health_check_rejects_a_null_config(void)
{
    TEST_ASSERT_FALSE(server_run_health_check(NULL));
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_health_check_passes_on_a_fully_valid_data_dir);
    RUN_TEST(test_health_check_fails_when_database_is_missing);
    RUN_TEST(test_health_check_fails_when_auth_token_is_missing);
    RUN_TEST(test_health_check_fails_when_cert_is_missing);
    RUN_TEST(test_health_check_rejects_a_null_config);
    return UNITY_END();
}
