#include "commands.h"
#include "handshake.h"
#include "log.h"
#include "secret_prompt.h"

#include <bunny_core/core.h>

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BUNNY_CLI_VERSION "0.1.0"

static void print_usage(const char *argv0)
{
    printf("Usage: %s [--unlock <secret>] <command>\n\n", argv0);
    printf("Commands:\n");
    printf("  --whoami                         Show which repository config bunny_cli resolved\n");
    printf("  --search <e621|inkbunny> <query> [--page N]\n");
    printf("                                    Run a live search, dumping the posts as JSON\n");
    printf("  --pool <pool_id>                  Dump an e621 pool's own metadata as JSON\n");
    printf("  --download [--jobs N] [--site <e621|inkbunny>] [<spec> ...]\n");
    printf("                                    Drain the download queue (default 3 workers); each\n");
    printf("                                    optional <spec> is \"pool:<id>\", \"search:<id>\", or a\n");
    printf("                                    plain tag query (under --site, e621 if omitted) --\n");
    printf("                                    every post it finds is queued first, then drained\n");
    printf("                                    along with everything already queued\n");
    printf("  --favorite <post_id> [--stars N]  Favorite a post (N is Inkbunny's 1-3 tier, ignored on e621)\n");
    printf("  --unfavorite <post_id>            Unfavorite a post\n");
    printf("  --vote <post_id> <score>          Vote on a post (score: -1, 0, or 1; e621 only)\n");
    printf("  --sync [search_id]                Sync due saved searches, or force one search by id\n");
    printf("  --blacklist-list <e621|inkbunny>  Dump a site's tag blacklist as JSON\n");
    printf("  --blacklist-add <e621|inkbunny> <tag>\n");
    printf("                                    Add a blacklist rule\n");
    printf("  --blacklist-remove <e621|inkbunny> <tag>\n");
    printf("                                    Remove a blacklist rule\n");
    printf("  --queue-list                      Dump the download queue as JSON\n");
    printf("  --stats                           Print row counts per database table and run an integrity check\n");
    printf("  --help                            Show this help\n");
    printf("  --version                         Show the version\n");
    printf("\n");
    printf("Global flags:\n");
    printf("  --unlock <secret>  The app's own app-lock PIN/password, if one is set -- prompted for\n");
    printf("                     interactively (not echoed) if omitted and the app turns out to be locked\n");
    printf("\n");
    printf("bunny_cli must sit in the same directory as the app's own executable --\n");
    printf("it briefly launches the app to learn its current repository config, which\n");
    printf("never touches disk or becomes visible to any other process.\n");
    printf("\n");
    printf("In networked mode, --stats isn't supported (the server has no REST endpoint\n");
    printf("for it) -- --download/--queue-list additionally need the app to report a\n");
    printf("local download-queue database path, see cli/README.md.\n");
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

/* Index of `flag` in argv, or -1 if not present -- for a command needing
 * its own positional arguments right after it (--search/--pool), unlike
 * every other flag here which is a bare switch or a single --flag value
 * pair findable via find_flag_value. */
static int find_flag_index(int argc, char **argv, const char *flag)
{
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], flag) == 0) {
            return i;
        }
    }
    return -1;
}

static bool parse_site(const char *s, bunny_db_site_t *out)
{
    if (strcmp(s, "e621") == 0) {
        *out = BUNNY_DB_SITE_E621;
        return true;
    }
    if (strcmp(s, "inkbunny") == 0) {
        *out = BUNNY_DB_SITE_INKBUNNY;
        return true;
    }
    return false;
}

/* Collects every argv token after --download's own index as a spec string
 * (see commands.h's own doc comment on bunny_cli_cmd_download for what a
 * spec is), skipping --jobs/--site/--unlock and their own value token --
 * both are global flags findable from anywhere in argv via find_flag_value,
 * not just after --download, so they must never be mistaken for a spec
 * themselves. `out_specs` must have room for at least argc entries (always
 * enough). Returns how many specs it found. */
static size_t collect_download_specs(int argc, char **argv, int download_index, const char **out_specs)
{
    size_t count = 0;
    for (int i = download_index + 1; i < argc; i++) {
        if (strcmp(argv[i], "--jobs") == 0 || strcmp(argv[i], "--site") == 0 || strcmp(argv[i], "--unlock") == 0) {
            i++; /* that flag's own value isn't a spec either */
            continue;
        }
        out_specs[count++] = argv[i];
    }
    return count;
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
    printf("downloadDestinationFolder: %s\n", payload->download_destination_folder ? payload->download_destination_folder : "(none)");
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

    int search_index = find_flag_index(argc, argv, "--search");
    int pool_index = find_flag_index(argc, argv, "--pool");
    int favorite_index = find_flag_index(argc, argv, "--favorite");
    int unfavorite_index = find_flag_index(argc, argv, "--unfavorite");
    int vote_index = find_flag_index(argc, argv, "--vote");
    bool wants_sync = has_flag(argc, argv, "--sync");
    int blacklist_list_index = find_flag_index(argc, argv, "--blacklist-list");
    int blacklist_add_index = find_flag_index(argc, argv, "--blacklist-add");
    int blacklist_remove_index = find_flag_index(argc, argv, "--blacklist-remove");
    bool wants_queue_list = has_flag(argc, argv, "--queue-list");
    int download_index = find_flag_index(argc, argv, "--download");
    bool wants_download = download_index >= 0;
    bool wants_stats = has_flag(argc, argv, "--stats");

    bool has_command = search_index >= 0 || pool_index >= 0 || favorite_index >= 0 || unfavorite_index >= 0 || vote_index >= 0 || wants_sync || blacklist_list_index >= 0 || blacklist_add_index >= 0 || blacklist_remove_index >= 0 || wants_queue_list || wants_download || wants_stats;
    if (!has_command) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "no command given, see --help");
        bunny_cli_handshake_payload_free(&payload);
        return 1;
    }

    /* Builds whichever half(s) of bunny_cli_context_t this mode actually
     * needs. `ctx.core` is the local download-queue db in BOTH modes
     * (standalone's one real database; networked's small queue-only db,
     * handshake's download_queue_db_path -- see bunny_cli_context_t's own
     * doc comment for why networked mode still needs one) -- opened
     * exactly once here rather than each command opening/closing its own,
     * and keeps the "failed to open the database" error in one place.
     * `ctx.rest` is additionally built for networked mode (bearer token +
     * pinned certificate), used for everything that actually needs the
     * server. A command with no networked implementation at all (--stats)
     * reports that itself (see commands.h). */
    bunny_cli_context_t ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.auto_favorite_on_download = payload.auto_favorite_on_download;
    ctx.auto_upvote_on_download = payload.auto_upvote_on_download;

    bunny_core_t *core = NULL;
    bunny_cli_rest_client_t rest_client;
    if (payload.mode == BUNNY_CLI_MODE_NETWORKED) {
        ctx.mode = BUNNY_CLI_MODE_NETWORKED;
        if (!bunny_cli_rest_client_init(&rest_client, payload.server_base_url, payload.bearer_token, payload.cert_fingerprint)) {
            bunny_cli_log(BUNNY_CLI_LOG_ERROR, "failed to set up the server connection");
            bunny_cli_handshake_payload_free(&payload);
            return 1;
        }
        ctx.rest = &rest_client;

        if (payload.download_queue_db_path) {
            bunny_core_config_t queue_config;
            memset(&queue_config, 0, sizeof(queue_config));
            queue_config.db_path = payload.download_queue_db_path;
            queue_config.user_agent = payload.download_queue_user_agent ? payload.download_queue_user_agent : "bunny_cli/1.0";
            queue_config.log_callback = bunny_cli_log_bunny_core_callback;

            if (bunny_core_open(&queue_config, &core) != BUNNY_CORE_OK) {
                bunny_cli_log(BUNNY_CLI_LOG_ERROR, "failed to open the download-queue database at %s", payload.download_queue_db_path);
                bunny_cli_rest_client_free(&rest_client);
                bunny_cli_handshake_payload_free(&payload);
                return 1;
            }
            ctx.core = core;
        }
        /* No download_queue_db_path at all (an older app build) -- every
         * command except --download/--queue-list still works fine with
         * ctx.core left NULL; those two report it clearly themselves. */
    } else {
        ctx.mode = BUNNY_CLI_MODE_STANDALONE;
        bunny_core_config_t config;
        memset(&config, 0, sizeof(config));
        config.db_path = payload.db_path;
        config.user_agent = payload.user_agent;
        config.log_callback = bunny_cli_log_bunny_core_callback;

        if (bunny_core_open(&config, &core) != BUNNY_CORE_OK) {
            bunny_cli_log(BUNNY_CLI_LOG_ERROR, "failed to open the database at %s", payload.db_path);
            bunny_cli_handshake_payload_free(&payload);
            return 1;
        }
        ctx.core = core;
    }

    int exit_code = 1;
    if (search_index >= 0) {
        if (search_index + 2 >= argc) {
            bunny_cli_log(BUNNY_CLI_LOG_ERROR, "--search needs <e621|inkbunny> <query>");
        } else {
            bunny_db_site_t site;
            if (!parse_site(argv[search_index + 1], &site)) {
                bunny_cli_log(BUNNY_CLI_LOG_ERROR, "unknown site \"%s\", expected e621 or inkbunny", argv[search_index + 1]);
            } else {
                const char *page_str = find_flag_value(argc, argv, "--page");
                int page = page_str ? (int)strtol(page_str, NULL, 10) : 1;
                exit_code = bunny_cli_cmd_search(&ctx, site, argv[search_index + 2], page);
            }
        }
    } else if (pool_index >= 0) {
        if (pool_index + 1 >= argc) {
            bunny_cli_log(BUNNY_CLI_LOG_ERROR, "--pool needs <pool_id>");
        } else {
            int64_t pool_id = strtoll(argv[pool_index + 1], NULL, 10);
            exit_code = bunny_cli_cmd_pool(&ctx, pool_id);
        }
    } else if (wants_download) {
        const char *jobs_str = find_flag_value(argc, argv, "--jobs");
        int jobs = jobs_str ? (int)strtol(jobs_str, NULL, 10) : 3;

        const char *site_str = find_flag_value(argc, argv, "--site");
        bunny_db_site_t spec_site = BUNNY_DB_SITE_E621;
        if (site_str && !parse_site(site_str, &spec_site)) {
            bunny_cli_log(BUNNY_CLI_LOG_ERROR, "unknown site \"%s\", expected e621 or inkbunny", site_str);
        } else {
            const char **specs = malloc(sizeof(char *) * (size_t)argc);
            size_t spec_count = collect_download_specs(argc, argv, download_index, specs);
            exit_code = bunny_cli_cmd_download(&ctx, payload.download_destination_folder, jobs, spec_site, specs, spec_count);
            free(specs);
        }
    } else if (favorite_index >= 0) {
        if (favorite_index + 1 >= argc) {
            bunny_cli_log(BUNNY_CLI_LOG_ERROR, "--favorite needs <post_id>");
        } else {
            int64_t post_id = strtoll(argv[favorite_index + 1], NULL, 10);
            const char *stars_str = find_flag_value(argc, argv, "--stars");
            int stars = stars_str ? (int)strtol(stars_str, NULL, 10) : -1;
            exit_code = bunny_cli_cmd_favorite_add(&ctx, post_id, stars);
        }
    } else if (unfavorite_index >= 0) {
        if (unfavorite_index + 1 >= argc) {
            bunny_cli_log(BUNNY_CLI_LOG_ERROR, "--unfavorite needs <post_id>");
        } else {
            int64_t post_id = strtoll(argv[unfavorite_index + 1], NULL, 10);
            exit_code = bunny_cli_cmd_favorite_remove(&ctx, post_id);
        }
    } else if (vote_index >= 0) {
        if (vote_index + 2 >= argc) {
            bunny_cli_log(BUNNY_CLI_LOG_ERROR, "--vote needs <post_id> <score>");
        } else {
            int64_t post_id = strtoll(argv[vote_index + 1], NULL, 10);
            int score = (int)strtol(argv[vote_index + 2], NULL, 10);
            exit_code = bunny_cli_cmd_vote(&ctx, post_id, score);
        }
    } else if (wants_sync) {
        const char *search_id_str = find_flag_value(argc, argv, "--sync");
        int64_t search_id = search_id_str ? strtoll(search_id_str, NULL, 10) : 0;
        exit_code = bunny_cli_cmd_sync(&ctx, search_id);
    } else if (blacklist_list_index >= 0) {
        if (blacklist_list_index + 1 >= argc) {
            bunny_cli_log(BUNNY_CLI_LOG_ERROR, "--blacklist-list needs <e621|inkbunny>");
        } else {
            bunny_db_site_t site;
            if (!parse_site(argv[blacklist_list_index + 1], &site)) {
                bunny_cli_log(BUNNY_CLI_LOG_ERROR, "unknown site \"%s\", expected e621 or inkbunny", argv[blacklist_list_index + 1]);
            } else {
                exit_code = bunny_cli_cmd_blacklist_list(&ctx, site);
            }
        }
    } else if (blacklist_add_index >= 0) {
        if (blacklist_add_index + 2 >= argc) {
            bunny_cli_log(BUNNY_CLI_LOG_ERROR, "--blacklist-add needs <e621|inkbunny> <tag>");
        } else {
            bunny_db_site_t site;
            if (!parse_site(argv[blacklist_add_index + 1], &site)) {
                bunny_cli_log(BUNNY_CLI_LOG_ERROR, "unknown site \"%s\", expected e621 or inkbunny", argv[blacklist_add_index + 1]);
            } else {
                exit_code = bunny_cli_cmd_blacklist_add(&ctx, site, argv[blacklist_add_index + 2]);
            }
        }
    } else if (blacklist_remove_index >= 0) {
        if (blacklist_remove_index + 2 >= argc) {
            bunny_cli_log(BUNNY_CLI_LOG_ERROR, "--blacklist-remove needs <e621|inkbunny> <tag>");
        } else {
            bunny_db_site_t site;
            if (!parse_site(argv[blacklist_remove_index + 1], &site)) {
                bunny_cli_log(BUNNY_CLI_LOG_ERROR, "unknown site \"%s\", expected e621 or inkbunny", argv[blacklist_remove_index + 1]);
            } else {
                exit_code = bunny_cli_cmd_blacklist_remove(&ctx, site, argv[blacklist_remove_index + 2]);
            }
        }
    } else if (wants_queue_list) {
        exit_code = bunny_cli_cmd_queue_list(&ctx);
    } else {
        exit_code = bunny_cli_cmd_stats(&ctx);
    }

    if (ctx.mode == BUNNY_CLI_MODE_NETWORKED) {
        bunny_cli_rest_client_free(&rest_client);
    }
    if (ctx.core) {
        bunny_core_close(ctx.core);
    }
    bunny_cli_handshake_payload_free(&payload);
    return exit_code;
}
