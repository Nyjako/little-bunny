#include "log.h"

#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#ifdef _WIN32
#include <io.h>
#include <windows.h>
#else
#include <unistd.h>
#endif

static bool g_color_enabled = false;

static bool stderr_is_tty(void)
{
#ifdef _WIN32
    return _isatty(_fileno(stderr)) != 0;
#else
    return isatty(STDERR_FILENO) != 0;
#endif
}

void bunny_cli_log_init(void)
{
#ifdef _WIN32
    HANDLE handle = GetStdHandle(STD_ERROR_HANDLE);
    DWORD mode = 0;
    if (handle != INVALID_HANDLE_VALUE && GetConsoleMode(handle, &mode)) {
        SetConsoleMode(handle, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
    }
#endif
    g_color_enabled = stderr_is_tty();
}

static const char *level_tag(bunny_cli_log_level_t level)
{
    switch (level) {
        case BUNNY_CLI_LOG_DEBUG:
            return "DEBUG";
        case BUNNY_CLI_LOG_INFO:
            return "INFO";
        case BUNNY_CLI_LOG_SUCCESS:
            return "OK";
        case BUNNY_CLI_LOG_WARN:
            return "WARN";
        case BUNNY_CLI_LOG_ERROR:
            return "ERROR";
    }
    return "?";
}

static const char *level_color(bunny_cli_log_level_t level)
{
    switch (level) {
        case BUNNY_CLI_LOG_DEBUG:
            return "\x1b[2m"; /* dim */
        case BUNNY_CLI_LOG_INFO:
            return "\x1b[36m"; /* cyan */
        case BUNNY_CLI_LOG_SUCCESS:
            return "\x1b[32m"; /* green */
        case BUNNY_CLI_LOG_WARN:
            return "\x1b[33m"; /* yellow */
        case BUNNY_CLI_LOG_ERROR:
            return "\x1b[31m"; /* red */
    }
    return "";
}

void bunny_cli_log(bunny_cli_log_level_t level, const char *fmt, ...)
{
    if (g_color_enabled) {
        fprintf(stderr, "%s[%s]\x1b[0m ", level_color(level), level_tag(level));
    } else {
        fprintf(stderr, "[%s] ", level_tag(level));
    }

    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);

    fprintf(stderr, "\n");
}

void bunny_cli_log_bunny_core_callback(void *user_data, const char *level, const char *message)
{
    (void)user_data;
    bunny_cli_log_level_t mapped = BUNNY_CLI_LOG_INFO;
    if (level) {
        if (strcmp(level, "ERROR") == 0) {
            mapped = BUNNY_CLI_LOG_ERROR;
        } else if (strcmp(level, "WARN") == 0) {
            mapped = BUNNY_CLI_LOG_WARN;
        }
    }
    bunny_cli_log(mapped, "%s", message ? message : "");
}
