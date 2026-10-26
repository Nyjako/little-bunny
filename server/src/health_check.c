#include "health_check.h"

#include <bunny_core/core.h>
#include <goblin/appdirs.h>
#include <goblin/fileio.h>
#include <openssl/pem.h>
#include <openssl/x509.h>

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static bool check_data_dir_writable(const char *data_dir)
{
    bool ok = data_dir && goblin_path_writable(data_dir);
    printf("%s  data_dir is writable (%s)\n", ok ? "PASS" : "FAIL", data_dir ? data_dir : "(none)");
    return ok;
}

/* Opening the database (bunny_core_open) is the same thing the real server
 * does on every normal startup -- idempotent CREATE TABLE IF NOT EXISTS/
 * migration bookkeeping, not the kind of write side effect the "no
 * auto-generation" rule above is about (that's specifically about not
 * minting a fresh auth_token/TLS cert just because --health happened to run
 * on a never-started data dir). */
static bool check_database(const char *data_dir)
{
    char *db_path = goblin_appdir_join(data_dir, "bunny.db");
    if (!db_path) {
        printf("FAIL  database: failed to build the db path\n");
        return false;
    }
    struct stat st;
    if (stat(db_path, &st) != 0) {
        printf("FAIL  database: %s does not exist yet\n", db_path);
        free(db_path);
        return false;
    }

    bunny_core_config_t core_config;
    memset(&core_config, 0, sizeof(core_config));
    core_config.db_path = db_path;
    core_config.user_agent = "LittleBunny-HealthCheck/1.0";

    bool ok = false;
    bunny_core_t *core = NULL;
    if (bunny_core_open(&core_config, &core) == BUNNY_CORE_OK) {
        bool integrity_ok = false;
        ok = bunny_core_integrity_check(core, &integrity_ok) == BUNNY_CORE_OK && integrity_ok;
        bunny_core_close(core);
    }
    free(db_path);
    printf("%s  database opens and passes PRAGMA integrity_check\n", ok ? "PASS" : "FAIL");
    return ok;
}

/* Reads the raw file rather than going through server_auth_load (which
 * generates a fresh token when one doesn't exist) -- a missing/malformed
 * token must surface as a FAIL here, not get silently papered over. */
static bool check_auth_token(const char *data_dir)
{
    char *token_path = goblin_appdir_join(data_dir, "auth_token");
    bool ok = false;
    if (token_path) {
        FILE *f = fopen(token_path, "rb");
        if (f) {
            char buf[80];
            size_t n = fread(buf, 1, sizeof(buf), f);
            fclose(f);
            while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r')) {
                n--;
            }
            ok = n == 64;
            for (size_t i = 0; ok && i < n; i++) {
                ok = isxdigit((unsigned char)buf[i]) != 0;
            }
        }
        free(token_path);
    }
    printf("%s  auth_token exists and is a valid 64-char hex token\n", ok ? "PASS" : "FAIL");
    return ok;
}

/* Same PEM-reading approach as qr.c's compute_cert_sha256, but also checks
 * expiry -- reads the raw file rather than server_tls_ensure_cert, which
 * generates a fresh self-signed cert when one doesn't exist. */
static bool check_tls_cert(const char *data_dir)
{
    char *pem_path = goblin_appdir_join(data_dir, "server.pem");
    bool ok = false;
    if (pem_path) {
        FILE *f = fopen(pem_path, "r");
        if (f) {
            X509 *cert = PEM_read_X509(f, NULL, NULL, NULL);
            fclose(f);
            if (cert) {
                ok = X509_cmp_current_time(X509_get0_notAfter(cert)) > 0;
                X509_free(cert);
            }
        }
        free(pem_path);
    }
    printf("%s  server.pem exists, parses, and is not expired\n", ok ? "PASS" : "FAIL");
    return ok;
}

bool server_run_health_check(const server_config_t *config)
{
    if (!config) {
        return false;
    }
    /* Every check always runs (left operand of && is unconditional), even
     * once one has already failed -- an operator wants the full picture,
     * not just the first problem found. */
    bool ok = true;
    ok = check_data_dir_writable(config->data_dir) && ok;
    ok = check_database(config->data_dir) && ok;
    ok = check_auth_token(config->data_dir) && ok;
    ok = check_tls_cert(config->data_dir) && ok;
    return ok;
}
