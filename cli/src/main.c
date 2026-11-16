#include "handshake.h"
#include "log.h"
#include "secret_prompt.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BUNNY_CLI_VERSION "0.1.0"

static void print_usage(const char *argv0)
{
    printf("Usage: %s [--unlock <secret>] <command>\n\n", argv0);
    printf("Commands:\n");
    printf("  --whoami           Show which repository config bunny_cli resolved via the app handshake\n");
    printf("  --help             Show this help\n");
    printf("  --version          Show the version\n");
    printf("\n");
    printf("Global flags:\n");
    printf("  --unlock <secret>  The app's own app-lock PIN/password, if one is set -- prompted for\n");
    printf("                     interactively (not echoed) if omitted and the app turns out to be locked\n");
    printf("\n");
    printf("bunny_cli must sit in the same directory as the app's own executable --\n");
    printf("it briefly launches the app to learn its current repository config, which\n");
    printf("never touches disk or becomes visible to any other process.\n");
}

static bool has_flag(int argc, char **argv, const char *flag)
{
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], flag) == 0) {
            return true;
        }
    }
    return false;
}

static const char *find_flag_value(int argc, char **argv, const char *flag)
{
    for (int i = 1; i < argc - 1; i++) {
        if (strcmp(argv[i], flag) == 0) {
            return argv[i + 1];
        }
    }
    return NULL;
}

/* Runs the handshake once with `supplied_secret`; on BUNNY_CLI_HANDSHAKE_LOCKED
 * with no secret supplied at all (the user never passed --unlock) and an
 * interactive stdin, prompts for one and retries exactly once more -- see
 * handshake.h's own protocol doc comment. Never retries more than that one
 * time, and never prompts at all for a script/CI run (no TTY) or when
 * --unlock was already given (a wrong --unlock fails outright rather than
 * silently falling back to an interactive prompt, which would be surprising
 * in a non-interactive context that happened to have a TTY attached). */
static bunny_cli_handshake_result_t run_handshake_with_retry(const char *app_exe_path, const char *supplied_secret, bunny_cli_handshake_payload_t *out)
{
    bunny_cli_handshake_result_t result = bunny_cli_handshake_run(app_exe_path, supplied_secret, out);
    if (result != BUNNY_CLI_HANDSHAKE_LOCKED || supplied_secret != NULL || !bunny_cli_stdin_is_tty()) {
        return result;
    }

    char prompted[256];
    bunny_cli_prompt_secret("App is locked, enter PIN/password: ", prompted, sizeof(prompted));
    return bunny_cli_handshake_run(app_exe_path, prompted, out);
}

static void print_whoami(const bunny_cli_handshake_payload_t *payload)
{
    switch (payload->mode) {
        case BUNNY_CLI_MODE_NONE:
            /* Handled by the caller before this is ever reached -- see
             * main()'s own mode == BUNNY_CLI_MODE_NONE check. */
            break;
        case BUNNY_CLI_MODE_STANDALONE:
            printf("mode: standalone\n");
            printf("dbPath: %s\n", payload->db_path);
            printf("userAgent: %s\n", payload->user_agent);
            break;
        case BUNNY_CLI_MODE_NETWORKED:
            printf("mode: networked\n");
            printf("serverBaseUrl: %s\n", payload->server_base_url);
            printf("bearerToken: (hidden, %zu chars)\n", strlen(payload->bearer_token));
            printf("certFingerprint: %s\n", payload->cert_fingerprint);
            break;
    }
}

int main(int argc, char **argv)
{
    bunny_cli_log_init();

    if (has_flag(argc, argv, "--help")) {
        print_usage(argv[0]);
        return 0;
    }
    if (has_flag(argc, argv, "--version")) {
        printf("bunny_cli %s\n", BUNNY_CLI_VERSION);
        return 0;
    }
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    char *app_exe_path = bunny_cli_find_app_executable();
    if (!app_exe_path) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "could not resolve bunny_cli's own executable path");
        return 1;
    }

    const char *supplied_secret = find_flag_value(argc, argv, "--unlock");
    bunny_cli_handshake_payload_t payload;
    bunny_cli_handshake_result_t result = run_handshake_with_retry(app_exe_path, supplied_secret, &payload);
    free(app_exe_path);

    if (result != BUNNY_CLI_HANDSHAKE_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "%s", bunny_cli_handshake_result_to_string(result));
        return 1;
    }

    if (payload.mode == BUNNY_CLI_MODE_NONE) {
        bunny_cli_log(BUNNY_CLI_LOG_WARN, "no repository configured yet -- run the app once and finish setup first");
        bunny_cli_handshake_payload_free(&payload);
        return 1;
    }

    if (has_flag(argc, argv, "--whoami")) {
        print_whoami(&payload);
        bunny_cli_handshake_payload_free(&payload);
        return 0;
    }

    bunny_cli_log(BUNNY_CLI_LOG_ERROR, "no command given, see --help");
    bunny_cli_handshake_payload_free(&payload);
    return 1;
}
