#include "status.h"

#include <bunny_common/http.h>
#include <goblin/appdirs.h>

#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

#include "auth.h"
#include "qr.h"
#include "tls.h"

static bool path_exists(const char *path)
{
    struct stat st;
    return path && stat(path, &st) == 0;
}

bool server_print_status(const server_config_t *config)
{
    if (!config) {
        return false;
    }

    printf("data_dir: %s\n", config->data_dir);
    printf("port: %d\n", config->port);
    printf("poll_interval_sec: %d\n", config->poll_interval_sec);

    server_auth_t *auth = server_auth_load(config->data_dir);
    if (!auth) {
        fprintf(stderr, "status: failed to load/generate the auth token\n");
        return false;
    }
    printf("bearer_token: %s\n", auth->token);
    server_auth_free(auth);

    /* Ensures server.pem exists (generating it on a genuinely never-started
     * data dir) before reading its fingerprint -- same precedent `--qr`
     * already set (qr.c's server_print_connection_qr), not something
     * `--status` needs to avoid: it's additive/idempotent, and by the time
     * the real service has ever started, this file already exists anyway. */
    char *cert_path = server_tls_ensure_cert(config->data_dir);
    free(cert_path);

    char *cert_sha256 = compute_cert_sha256(config->data_dir);
    if (!cert_sha256) {
        fprintf(stderr, "status: failed to read server.pem for its fingerprint\n");
        return false;
    }
    printf("cert_sha256: %s\n", cert_sha256);
    free(cert_sha256);

    bunny_http_transport_t transport = bunny_http_curl_transport();
    char *public_ip = fetch_public_ip(&transport, config->user_agent);
    if (public_ip) {
        printf("server_url: https://%s:%d\n", public_ip, config->port);
        free(public_ip);
    } else {
        printf("server_url: (couldn't determine public IP -- no internet access?)\n");
    }

    char *db_path = goblin_appdir_join(config->data_dir, "bunny.db");
    struct stat db_st;
    if (db_path && stat(db_path, &db_st) == 0) {
        printf("bunny.db size: %lld bytes\n", (long long)db_st.st_size);
    } else {
        printf("bunny.db size: (not found yet)\n");
    }
    free(db_path);

    char *ready_marker = goblin_appdir_join(config->data_dir, "update-ready");
    printf("pending update: %s\n", path_exists(ready_marker) ? "yes (staged, pending restart)" : "none");
    free(ready_marker);

    return true;
}
