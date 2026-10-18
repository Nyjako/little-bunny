#include "unity.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "bunny_core/core.h"
#include "bunny_db/db.h"

static bunny_core_t *g_core;

void setUp(void)
{
    bunny_core_config_t config;
    memset(&config, 0, sizeof(config));
    config.db_path = ":memory:";
    config.user_agent = "bunny-tests/1.0 (unit tests)";

    bunny_core_result_t result = bunny_core_open(&config, &g_core);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_NOT_NULL(g_core);
}

void tearDown(void)
{
    bunny_core_close(g_core);
    g_core = NULL;
}

void test_open_close(void)
{
    bunny_core_close(NULL);
}

void test_account_set_and_get(void)
{
    bunny_core_result_t result = bunny_core_account_set(g_core, BUNNY_DB_SITE_E621, "someuser", "someapikey");
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    bunny_db_account_t account;
    result = bunny_core_account_get(g_core, BUNNY_DB_SITE_E621, &account);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL_STRING("someuser", account.username);
    TEST_ASSERT_EQUAL_STRING("someapikey", account.secret);
    bunny_db_account_free(&account);
}

void test_account_set_upserts(void)
{
    bunny_core_account_set(g_core, BUNNY_DB_SITE_E621, "user1", "secret1");
    bunny_core_account_set(g_core, BUNNY_DB_SITE_E621, "user2", "secret2");

    bunny_db_account_t account;
    bunny_core_account_get(g_core, BUNNY_DB_SITE_E621, &account);
    TEST_ASSERT_EQUAL_STRING("user2", account.username);
    TEST_ASSERT_EQUAL_STRING("secret2", account.secret);
    bunny_db_account_free(&account);
}

void test_account_get_not_found(void)
{
    bunny_db_account_t account;
    bunny_core_result_t result = bunny_core_account_get(g_core, BUNNY_DB_SITE_INKBUNNY, &account);
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_NOT_FOUND, result);
}

void test_account_delete(void)
{
    bunny_core_account_set(g_core, BUNNY_DB_SITE_E621, "user", "secret");

    bunny_core_result_t result = bunny_core_account_delete(g_core, BUNNY_DB_SITE_E621);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    bunny_db_account_t account;
    result = bunny_core_account_get(g_core, BUNNY_DB_SITE_E621, &account);
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_NOT_FOUND, result);
}

void test_backup_database_creates_a_timestamped_file(void)
{
    bunny_core_account_set(g_core, BUNNY_DB_SITE_E621, "someuser", "someapikey");

    char template[] = "/tmp/bunny_core_backup_test_XXXXXX";
    char *backups_dir = mkdtemp(template);
    TEST_ASSERT_NOT_NULL(backups_dir);

    bunny_core_result_t result = bunny_core_backup_database(g_core, backups_dir);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    /* Find the one file bunny_core_backup_database just wrote -- its name
     * embeds a unix timestamp we don't control exactly, so scan the dir
     * rather than guessing it (same approach the scheduler's own pruning
     * logic will use to find backups to keep/delete, M14.5). */
    DIR *dir = opendir(backups_dir);
    TEST_ASSERT_NOT_NULL(dir);
    char found_path[1100] = {0};
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (strncmp(entry->d_name, "bunny_", 6) == 0) {
            snprintf(found_path, sizeof(found_path), "%s/%s", backups_dir, entry->d_name);
            break;
        }
    }
    closedir(dir);
    TEST_ASSERT_NOT_EQUAL(0, found_path[0]);

    bunny_db_t *restored = NULL;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_open(found_path, &restored));
    bunny_db_account_t account;
    TEST_ASSERT_EQUAL(BUNNY_DB_OK, bunny_db_account_get(restored, BUNNY_DB_SITE_E621, &account));
    TEST_ASSERT_EQUAL_STRING("someuser", account.username);
    bunny_db_account_free(&account);
    bunny_db_close(restored);

    remove(found_path);
    rmdir(backups_dir);
}

void test_backup_database_rejects_null_args(void)
{
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_INVALID_ARG, bunny_core_backup_database(NULL, "/tmp"));
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_INVALID_ARG, bunny_core_backup_database(g_core, NULL));
}

/* Every other test in this file runs against setUp's ":memory:" core, which
 * never opens a read pool at all (see bunny_core_open's open_read_pool --
 * ":memory:" has no shared storage for a pool of connections to see). This
 * is the one test that opens a REAL on-disk database, so it's the only one
 * that actually exercises has_read_pool's true branch (M25) -- a write via
 * core->db followed immediately by a read through the pool (round-robining
 * across all BUNNY_CORE_READ_POOL_SIZE slots, not just whichever one happens
 * to be picked first) must see that write, proving the pool's connections
 * are genuinely backed by the same file rather than, say, a typo'd path. */
void test_read_pool_sees_writes_on_a_real_file_backed_database(void)
{
    char dir_template[] = "/tmp/bunny_core_read_pool_test_XXXXXX";
    char *dir = mkdtemp(dir_template);
    TEST_ASSERT_NOT_NULL(dir);
    char db_path[600];
    snprintf(db_path, sizeof(db_path), "%s/test.db", dir);

    bunny_core_config_t config;
    memset(&config, 0, sizeof(config));
    config.db_path = db_path;
    config.user_agent = "bunny-tests/1.0 (read pool)";

    bunny_core_t *core = NULL;
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, bunny_core_open(&config, &core));

    int64_t search_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, bunny_core_search_create(core, BUNNY_DB_SITE_E621, "wolves", "wolf", 24, NULL, &search_id));

    /* More calls than BUNNY_CORE_READ_POOL_SIZE so every slot in the pool
     * gets its turn via the round-robin -- each one needs to see the write
     * above, not just whichever slot a single call happens to land on. */
    for (int i = 0; i < 10; i++) {
        bunny_db_search_list_t list;
        TEST_ASSERT_EQUAL(BUNNY_CORE_OK, bunny_core_search_list(core, &list));
        TEST_ASSERT_EQUAL(1, list.count);
        TEST_ASSERT_EQUAL(search_id, list.items[0].id);
        bunny_db_search_list_free(&list);
    }

    bunny_core_close(core);
    remove(db_path);
    char wal_path[620], shm_path[620];
    snprintf(wal_path, sizeof(wal_path), "%s-wal", db_path);
    snprintf(shm_path, sizeof(shm_path), "%s-shm", db_path);
    remove(wal_path);
    remove(shm_path);
    rmdir(dir);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_open_close);
    RUN_TEST(test_account_set_and_get);
    RUN_TEST(test_account_set_upserts);
    RUN_TEST(test_account_get_not_found);
    RUN_TEST(test_account_delete);
    RUN_TEST(test_backup_database_creates_a_timestamped_file);
    RUN_TEST(test_backup_database_rejects_null_args);
    RUN_TEST(test_read_pool_sees_writes_on_a_real_file_backed_database);
    return UNITY_END();
}
