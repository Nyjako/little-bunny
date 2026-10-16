#ifndef BUNNY_SERVER_LOG_H
#define BUNNY_SERVER_LOG_H

#include <stddef.h>

/* Process-wide ring buffer logger -- not tied to server_context_t, since
 * there's only ever one server process per instance to log for. Every
 * server_log() call writes a timestamped line to stdout (so `journalctl -u
 * bunny-server` keeps working exactly as before) and also keeps the most
 * recent lines in memory so the authenticated GET /logs route can hand them
 * to a client with no SSH access to the box. */

/* Must be called exactly once, before any other server_log* call, and before
 * any second thread could possibly be calling server_log* concurrently --
 * server_app_start() does this as its very first statement, and the log
 * test suite does it once in setUp(). Needed because CRITICAL_SECTION (this
 * module's mutex on Windows, see bunny_common/thread.h) has no static-
 * initializer equivalent to pthread_mutex_t's PTHREAD_MUTEX_INITIALIZER, so
 * the old `static pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;` approach
 * doesn't port. Safe to call more than once (idempotent). */
void server_log_init(void);

/* printf-style; `level` is a short tag like "INFO"/"WARN"/"ERROR". */
void server_log(const char *level, const char *fmt, ...)
#if defined(__GNUC__) || defined(__clang__)
    __attribute__((format(printf, 2, 3)))
#endif
    ;

/* Returns a newly allocated array of newly allocated strings, oldest-first
 * (matching how `journalctl -f` reads) -- caller frees each string, then the
 * array itself. Returns 0 (and sets *out_lines to NULL) if nothing has been
 * logged yet. */
size_t server_log_snapshot(char ***out_lines);

/* Clears the buffer. Only meaningful for test isolation between cases --
 * a real server process never needs to call this, since it exits instead. */
void server_log_reset(void);

#endif /* BUNNY_SERVER_LOG_H */
