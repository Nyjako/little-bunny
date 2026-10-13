#include "log.h"

#include <goblin/cstr.h>

#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define SERVER_LOG_CAPACITY 200

static char *g_lines[SERVER_LOG_CAPACITY];
static size_t g_count = 0; /* valid entries, caps at SERVER_LOG_CAPACITY */
static size_t g_next = 0;  /* next write index, wraps */
static pthread_mutex_t g_log_mutex = PTHREAD_MUTEX_INITIALIZER;

void server_log(const char *level, const char *fmt, ...)
{
    char timestamp[32];
    time_t now = time(NULL);
    struct tm tm_utc;
    gmtime_r(&now, &tm_utc);
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%SZ", &tm_utc);

    char message[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(message, sizeof(message), fmt, args);
    va_end(args);

    char line[1100];
    snprintf(line, sizeof(line), "[%s] [%s] %s", timestamp, level, message);

    fprintf(stdout, "%s\n", line);
    fflush(stdout);

    pthread_mutex_lock(&g_log_mutex);
    free(g_lines[g_next]);
    g_lines[g_next] = goblin_copy_cstr(line);
    g_next = (g_next + 1) % SERVER_LOG_CAPACITY;
    if (g_count < SERVER_LOG_CAPACITY) {
        g_count++;
    }
    pthread_mutex_unlock(&g_log_mutex);
}

size_t server_log_snapshot(char ***out_lines)
{
    pthread_mutex_lock(&g_log_mutex);
    size_t count = g_count;
    char **copy = NULL;
    if (count > 0) {
        copy = malloc(count * sizeof(char *));
        if (!copy) {
            pthread_mutex_unlock(&g_log_mutex);
            *out_lines = NULL;
            return 0;
        }
        /* If the buffer hasn't wrapped yet, the oldest entry is simply
         * g_lines[0]; once it has, g_next points at the slot about to be
         * overwritten next, which is also the current oldest entry. */
        size_t start = (g_count < SERVER_LOG_CAPACITY) ? 0 : g_next;
        for (size_t i = 0; i < count; i++) {
            copy[i] = goblin_copy_cstr(g_lines[(start + i) % SERVER_LOG_CAPACITY]);
        }
    }
    pthread_mutex_unlock(&g_log_mutex);

    *out_lines = copy;
    return count;
}

void server_log_reset(void)
{
    pthread_mutex_lock(&g_log_mutex);
    for (size_t i = 0; i < SERVER_LOG_CAPACITY; i++) {
        free(g_lines[i]);
        g_lines[i] = NULL;
    }
    g_count = 0;
    g_next = 0;
    pthread_mutex_unlock(&g_log_mutex);
}
