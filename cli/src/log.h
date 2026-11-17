#ifndef BUNNY_CLI_LOG_H
#define BUNNY_CLI_LOG_H

#include <goblin/log.h>

#include <string.h>

/* Leveled, colored stderr logging for bunny_cli -- stdout stays reserved for
 * a command's own data (e.g. JSON a user might pipe into `jq`). Thin
 * forwarding wrappers over GOBLIN's own goblin_log (vendored) -- bunny_cli
 * used to hand-roll this itself (TTY detection, ANSI color, Windows VT100
 * enablement), now upstreamed into GOBLIN, so this just delegates. Every
 * existing bunny_cli_log* call site is unchanged; bunny_cli_log is a macro
 * rather than a bunny_common/thread.h-style static inline function because
 * it has to forward a variadic call. */

typedef goblin_log_level bunny_cli_log_level_t;

#define BUNNY_CLI_LOG_DEBUG GOBLIN_LOG_DEBUG
#define BUNNY_CLI_LOG_INFO GOBLIN_LOG_INFO
#define BUNNY_CLI_LOG_SUCCESS GOBLIN_LOG_SUCCESS
#define BUNNY_CLI_LOG_WARN GOBLIN_LOG_WARN
#define BUNNY_CLI_LOG_ERROR GOBLIN_LOG_ERROR

#define bunny_cli_log_init() goblin_log_init()
#define bunny_cli_log(level, ...) goblin_log((level), __VA_ARGS__)

/* Matches bunny_core_log_fn's signature (bunny_core/core.h) -- pass this
 * directly as bunny_core_config_t.log_callback so bunny_core's own
 * sync/progress lines get the same colored treatment for free. user_data is
 * unused. The one piece of this file that isn't just a forwarding wrapper:
 * bunny_core's own "ERROR"/"WARN"/other string levels aren't goblin_log's
 * enum, so this still has to map between them. */
static inline void bunny_cli_log_bunny_core_callback(void *user_data, const char *level, const char *message)
{
    (void)user_data;
    goblin_log_level mapped = GOBLIN_LOG_INFO;
    if (level) {
        if (strcmp(level, "ERROR") == 0) {
            mapped = GOBLIN_LOG_ERROR;
        } else if (strcmp(level, "WARN") == 0) {
            mapped = GOBLIN_LOG_WARN;
        }
    }
    goblin_log(mapped, "%s", message ? message : "");
}

#endif /* BUNNY_CLI_LOG_H */
