#include "bunny_core/core.h"

#include <goblin/cstr.h>

#include <stdlib.h>
#include <string.h>

#include "internal.h"

/* Tears down whatever subset of the read pool got opened before a failure
 * partway through -- shared by the "ran out of read connections" and
 * "ran out of read mutexes" failure paths in bunny_core_open below, each of
 * which needs to stop at a different point. */
static void close_read_pool(bunny_core_t *core, size_t opened_dbs, size_t opened_mutexes)
{
    for (size_t i = 0; i < opened_mutexes; i++) {
        bunny_mutex_destroy(&core->read_mutexes[i]);
    }
    for (size_t i = 0; i < opened_dbs; i++) {
        bunny_db_close(core->read_dbs[i]);
    }
}

/* Opens BUNNY_CORE_READ_POOL_SIZE extra connections to the same database
 * file for bunny_core_db_read_lock to hand out (M25) -- skipped entirely
 * for ":memory:" (every test's db_path), since SQLite gives each ":memory:"
 * open its own independent, empty database that could never see what the
 * write connection writes. core->has_read_pool stays false in that case,
 * and bunny_core_db_read_lock falls back to db_mutex/db, same as before
 * this existed. Always runs strictly after core->db itself is fully open
 * (never concurrently with it) so bunny_db_open's own schema/migration work
 * race-free -- by the time any read connection opens, schema_migrations
 * already shows every migration applied, so its own redundant migration
 * pass is just a handful of no-op SELECT checks. */
static bunny_core_result_t open_read_pool(bunny_core_t *core, const char *db_path)
{
    if (strcmp(db_path, ":memory:") == 0) {
        core->has_read_pool = false;
        return BUNNY_CORE_OK;
    }

    size_t opened_dbs = 0;
    for (; opened_dbs < BUNNY_CORE_READ_POOL_SIZE; opened_dbs++) {
        if (bunny_db_open(db_path, &core->read_dbs[opened_dbs]) != BUNNY_DB_OK) {
            close_read_pool(core, opened_dbs, 0);
            return BUNNY_CORE_ERR_UNKNOWN;
        }
    }

    size_t opened_mutexes = 0;
    for (; opened_mutexes < BUNNY_CORE_READ_POOL_SIZE; opened_mutexes++) {
        if (bunny_mutex_init(&core->read_mutexes[opened_mutexes]) != 0) {
            close_read_pool(core, opened_dbs, opened_mutexes);
            return BUNNY_CORE_ERR_UNKNOWN;
        }
    }

    if (bunny_mutex_init(&core->read_rr_mutex) != 0) {
        close_read_pool(core, opened_dbs, opened_mutexes);
        return BUNNY_CORE_ERR_UNKNOWN;
    }

    core->has_read_pool = true;
    return BUNNY_CORE_OK;
}

bunny_core_result_t bunny_core_open(const bunny_core_config_t *config, bunny_core_t **out_core)
{
    if (!config || !config->db_path || !config->user_agent || !out_core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }

    bunny_core_t *core = calloc(1, sizeof(bunny_core_t));
    if (!core) {
        return BUNNY_CORE_ERR_UNKNOWN;
    }

    bunny_db_result_t result = bunny_db_open(config->db_path, &core->db);
    if (result != BUNNY_DB_OK) {
        free(core);
        return bunny_core_map_db_result(result);
    }

    if (bunny_mutex_init(&core->db_mutex) != 0) {
        bunny_db_close(core->db);
        free(core);
        return BUNNY_CORE_ERR_UNKNOWN;
    }
    if (bunny_mutex_init(&core->sync_mutex) != 0) {
        bunny_mutex_destroy(&core->db_mutex);
        bunny_db_close(core->db);
        free(core);
        return BUNNY_CORE_ERR_UNKNOWN;
    }

    bunny_core_result_t read_pool_result = open_read_pool(core, config->db_path);
    if (read_pool_result != BUNNY_CORE_OK) {
        bunny_mutex_destroy(&core->sync_mutex);
        bunny_mutex_destroy(&core->db_mutex);
        bunny_db_close(core->db);
        free(core);
        return read_pool_result;
    }

    core->user_agent = goblin_copy_cstr(config->user_agent);
    core->e621_transport = config->e621_transport;
    core->inkbunny_transport = config->inkbunny_transport;
    core->min_request_interval_sec = config->min_request_interval_sec;
    core->log_callback = config->log_callback;
    core->log_user_data = config->log_user_data;

    *out_core = core;
    return BUNNY_CORE_OK;
}

void bunny_core_close(bunny_core_t *core)
{
    if (!core) {
        return;
    }
    if (core->has_read_pool) {
        bunny_mutex_destroy(&core->read_rr_mutex);
        close_read_pool(core, BUNNY_CORE_READ_POOL_SIZE, BUNNY_CORE_READ_POOL_SIZE);
    }
    bunny_mutex_destroy(&core->sync_mutex);
    bunny_mutex_destroy(&core->db_mutex);
    bunny_db_close(core->db);
    free(core->user_agent);
    free(core);
}
