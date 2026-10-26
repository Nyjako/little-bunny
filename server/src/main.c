#include <bunny_common/http.h>
#include <bunny_common/thread.h>
#include <bunny_core/core.h>
#include <goblin/appdirs.h>

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef _WIN32
#include <sys/wait.h>
#include <unistd.h>
#endif

#include "app.h"
#include "config.h"
#include "health_check.h"
#include "log.h"
#include "qr.h"
#include "status.h"
#include "updater.h"

static volatile sig_atomic_t g_shutdown_requested = 0;

static void handle_shutdown_signal(int signum)
{
    (void)signum;
    g_shutdown_requested = 1;
}

/* Shared by every one-shot CLI flag below that reads this deployment's own
 * data (--qr/--status/--health/--db-stats/--update): a manual invocation
 * runs in a plain shell with no BUNNY_SERVER_DATA_DIR override (unlike the
 * real service, always launched by systemd with it already set, see
 * deploy/bunny-server.service's Environment= line) -- falling through to
 * server_config_load()'s per-invoking-user XDG default would silently
 * read/generate throwaway files that have nothing to do with the actually-
 * running production server. Defaulting to the real deployment's
 * StateDirectory instead matches deploy/dump_server_info.sh's own hardcoded
 * assumption -- still overridable via the env var for any other deployment
 * layout. */
static void default_data_dir_if_unset(void)
{
    if (!getenv("BUNNY_SERVER_DATA_DIR")) {
        setenv("BUNNY_SERVER_DATA_DIR", "/var/lib/bunny-server", 1);
    }
}

static void print_usage(void)
{
    printf("bunny_server (build %d)\n", BUNNY_BUILD_NUMBER);
    printf("https://github.com/Nyjako/little-bunny\n\n");
    printf("Usage: bunny_server [flag]\n\n");
    printf("Running with no flag starts the server itself.\n\n");
    printf("Flags:\n");
    printf("  --help, -h       Show this message\n");
    printf("  --version, -v    Print the build number and exit\n");
    printf("  --qr             Print a connection QR code for the app's \"Networked\" setup\n");
    printf("  --status         Print data dir/port/token/cert/public IP info -- safe to run while the service is live\n");
    printf("  --health         Run pass/fail sanity checks (exit 0/1) -- safe to run while the service is live\n");
    printf("  --db-stats       Print row counts per database table -- safe to run while the service is live\n");
    printf("  --update         Check for and stage an update now -- needs root, stops/restarts the bunny-server\n");
    printf("                   service itself (Linux/systemd only)\n");
}

#ifndef _WIN32
/* Fork/exec `systemctl <action> bunny-server` directly (no shell -- same
 * no-injection-surface reasoning as bunny_updater_extract_tar_gz's own
 * `tar` invocation in updater.c, even though both arguments here are
 * internally constructed, never user input). */
static bool run_systemctl(const char *action)
{
    pid_t pid = fork();
    if (pid < 0) {
        return false;
    }
    if (pid == 0) {
        execlp("systemctl", "systemctl", action, "bunny-server", (char *)NULL);
        _exit(127); /* execlp failed (systemctl not on PATH, etc.) */
    }
    int status = 0;
    if (waitpid(pid, &status, 0) != pid) {
        return false;
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}
#endif

int main(int argc, char **argv)
{
    /* Used by the updater (updater.c, M23) after extracting a staged
     * release to confirm the new binary is actually the version it claims
     * to be, before the systemd ExecStartPre=+ helper installs it over the
     * live one -- also handy for plain ops/debugging ("what's running"). */
    if (argc > 1 && (strcmp(argv[1], "--version") == 0 || strcmp(argv[1], "-v") == 0)) {
        printf("%d\n", BUNNY_BUILD_NUMBER);
        return 0;
    }

    if (argc > 1 && (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0)) {
        print_usage();
        return 0;
    }

    /* Prints a QR code (+ the raw JSON, for manual copy-paste) encoding this
     * server's own connection info -- scannable by the app's "Networked"
     * setup screen instead of typing the server URL/bearer token/cert
     * fingerprint in by hand. Doesn't start the server itself (see qr.c's
     * own doc comment for why that's fine even on a never-before-run data
     * dir). */
    if (argc > 1 && strcmp(argv[1], "--qr") == 0) {
        default_data_dir_if_unset();
        server_config_t *qr_config = server_config_load();
        if (!qr_config) {
            fprintf(stderr, "failed to load server config\n");
            return 1;
        }
        bool ok = server_print_connection_qr(qr_config);
        server_config_free(qr_config);
        return ok ? 0 : 1;
    }

    /* Informational dump of this deployment's local state -- effectively
     * deploy/dump_server_info.sh folded into the binary. Read-only, safe to
     * run while the real service is live. */
    if (argc > 1 && strcmp(argv[1], "--status") == 0) {
        default_data_dir_if_unset();
        server_config_t *status_config = server_config_load();
        if (!status_config) {
            fprintf(stderr, "failed to load server config\n");
            return 1;
        }
        bool ok = server_print_status(status_config);
        server_config_free(status_config);
        return ok ? 0 : 1;
    }

    /* Pass/fail sanity checks (exit 0/1) suitable for monitoring/cron --
     * read-only, safe to run while the real service is live. */
    if (argc > 1 && strcmp(argv[1], "--health") == 0) {
        default_data_dir_if_unset();
        server_config_t *health_config = server_config_load();
        if (!health_config) {
            fprintf(stderr, "failed to load server config\n");
            return 1;
        }
        bool ok = server_run_health_check(health_config);
        server_config_free(health_config);
        return ok ? 0 : 1;
    }

    /* Row count per database table -- read-only, safe to run while the real
     * service is live. */
    if (argc > 1 && strcmp(argv[1], "--db-stats") == 0) {
        default_data_dir_if_unset();
        server_config_t *stats_config = server_config_load();
        if (!stats_config) {
            fprintf(stderr, "failed to load server config\n");
            return 1;
        }

        char *stats_db_path = goblin_appdir_join(stats_config->data_dir, "bunny.db");
        bunny_core_config_t stats_core_config;
        memset(&stats_core_config, 0, sizeof(stats_core_config));
        stats_core_config.db_path = stats_db_path;
        stats_core_config.user_agent = stats_config->user_agent;

        bunny_core_t *stats_core = NULL;
        if (!stats_db_path || bunny_core_open(&stats_core_config, &stats_core) != BUNNY_CORE_OK) {
            fprintf(stderr, "db-stats: failed to open the database\n");
            free(stats_db_path);
            server_config_free(stats_config);
            return 1;
        }
        free(stats_db_path);

        bunny_db_tag_stat_list_t table_stats;
        bunny_core_result_t result = bunny_core_table_stats(stats_core, &table_stats);
        bunny_core_close(stats_core);
        server_config_free(stats_config);
        if (result != BUNNY_CORE_OK) {
            fprintf(stderr, "db-stats: failed to query table row counts\n");
            return 1;
        }
        for (size_t i = 0; i < table_stats.count; i++) {
            printf("%s: %d\n", table_stats.items[i].name, table_stats.items[i].count);
        }
        bunny_db_tag_stat_list_free(&table_stats);
        return 0;
    }

    /* Forces an immediate update check/stage, bypassing the scheduler's own
     * 24h throttle -- stops the live systemd service first (it writes to
     * the same data_dir/update-staging/ the service's own scheduler tick
     * can be concurrently touching) and always restarts it afterward,
     * regardless of whether an update was found. Needs root both for that
     * and to read /var/lib/bunny-server's root/DynamicUser-owned files.
     * Linux/systemd only -- updater.c itself is never compiled into the
     * Windows server build (no self-update story for a Windows service),
     * and there's no equivalent Windows service to stop/start anyway. */
    if (argc > 1 && strcmp(argv[1], "--update") == 0) {
#ifdef _WIN32
        fprintf(stderr, "--update is not supported on Windows (no self-update story for a Windows service yet)\n");
        return 1;
#else
        if (geteuid() != 0) {
            fprintf(stderr, "--update needs root to stop/restart the bunny-server service and read its data directory -- re-run with sudo\n");
            return 1;
        }
        default_data_dir_if_unset();
        server_config_t *update_config = server_config_load();
        if (!update_config) {
            fprintf(stderr, "failed to load server config\n");
            return 1;
        }

        printf("Stopping bunny-server service...\n");
        if (!run_systemctl("stop")) {
            fprintf(stderr, "failed to stop the bunny-server service -- aborting without touching anything\n");
            server_config_free(update_config);
            return 1;
        }

        server_log_init();
        bunny_http_transport_t update_transport = bunny_http_curl_transport();
        bool restart_requested = false;
        bunny_updater_force_check_and_stage(&update_transport, update_config->data_dir, update_config->user_agent, &restart_requested);

        printf("Starting bunny-server service...\n");
        bool restarted = run_systemctl("start");
        server_config_free(update_config);
        if (!restarted) {
            fprintf(stderr, "bunny-server FAILED to restart -- it is currently STOPPED, start it manually: sudo systemctl start bunny-server\n");
            return 1;
        }
        return 0;
#endif
    }

    server_config_t *config = server_config_load();
    if (!config) {
        fprintf(stderr, "failed to load server config\n");
        return 1;
    }

    char *db_path = goblin_appdir_join(config->data_dir, "bunny.db");
    if (!db_path) {
        fprintf(stderr, "failed to build database path\n");
        server_config_free(config);
        return 1;
    }

    bunny_core_config_t core_config;
    memset(&core_config, 0, sizeof(core_config));
    core_config.db_path = db_path;
    core_config.user_agent = config->user_agent;

    server_app_t *app = server_app_start(&core_config, config->data_dir, config->port, config->poll_interval_sec);
    free(db_path);
    if (!app) {
        fprintf(stderr, "failed to start server\n");
        server_config_free(config);
        return 1;
    }

    server_log("INFO", "bunny_server listening on https://0.0.0.0:%d", config->port);

    signal(SIGINT, handle_shutdown_signal);
    signal(SIGTERM, handle_shutdown_signal);
    while (!g_shutdown_requested) {
        bunny_sleep_seconds(1);
    }

    server_log("INFO", "shutting down...");
    server_app_stop(app);
    server_config_free(config);
    return 0;
}
