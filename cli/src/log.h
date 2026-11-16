#ifndef BUNNY_CLI_LOG_H
#define BUNNY_CLI_LOG_H

#ifdef __cplusplus
extern "C" {
#endif

/* Leveled, colored stderr logging for bunny_cli -- stdout stays reserved for
 * a command's own data (e.g. JSON a user might pipe into `jq`). */
typedef enum
{
    BUNNY_CLI_LOG_DEBUG,
    BUNNY_CLI_LOG_INFO,
    BUNNY_CLI_LOG_SUCCESS,
    BUNNY_CLI_LOG_WARN,
    BUNNY_CLI_LOG_ERROR,
} bunny_cli_log_level_t;

/* Call once at startup, before any bunny_cli_log* call. Detects whether
 * stderr is a real terminal -- color is skipped otherwise (piped/redirected
 * output stays clean, e.g. `bunny_cli --download > log.txt`) -- and, on
 * Windows, enables ANSI escape processing on the console handle so the
 * codes this module writes actually render instead of printing as literal
 * garbage (falls back to plain text if that call fails, e.g. a very old
 * console host). */
void bunny_cli_log_init(void);

/* printf-style. */
void bunny_cli_log(bunny_cli_log_level_t level, const char *fmt, ...)
#if defined(__GNUC__) || defined(__clang__)
    __attribute__((format(printf, 2, 3)))
#endif
    ;

/* Matches bunny_core_log_fn's signature (bunny_core/core.h) -- pass this
 * directly as bunny_core_config_t.log_callback so bunny_core's own
 * sync/progress lines get the same colored treatment for free. user_data is
 * unused. */
void bunny_cli_log_bunny_core_callback(void *user_data, const char *level, const char *message);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_CLI_LOG_H */
