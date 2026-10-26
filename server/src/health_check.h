#ifndef BUNNY_SERVER_HEALTH_CHECK_H
#define BUNNY_SERVER_HEALTH_CHECK_H

#include <stdbool.h>

#include "config.h"

/* Runs independent, read-only sanity checks against this deployment's
 * data_dir -- deliberately does NOT reuse server_auth_load/
 * server_tls_ensure_cert, which auto-generate on a missing file (a health
 * check must never have write side effects). Prints one PASS/FAIL line per
 * check to stdout, suitable for monitoring/cron. Returns true only if every
 * check passed -- `bunny_server --health` (main.c) maps this straight to its
 * own exit code. Safe to run while the real service is live (read-only). */
bool server_run_health_check(const server_config_t *config);

#endif /* BUNNY_SERVER_HEALTH_CHECK_H */
