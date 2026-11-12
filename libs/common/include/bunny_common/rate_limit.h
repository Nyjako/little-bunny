#ifndef BUNNY_COMMON_RATE_LIMIT_H
#define BUNNY_COMMON_RATE_LIMIT_H

#include <goblin/rate_limit.h>

/* Shared by libe621/libinkbunny's client.c, both of which pace outgoing
 * requests to min_request_interval_sec apart. Built on GOBLIN's own
 * goblin_rate_limiter -- was previously a thin wrapper around goblin_timer
 * plus hand-rolled Win32 Sleep()/POSIX nanosleep(), which is now exactly
 * what goblin_rate_limiter itself does internally. */
typedef goblin_rate_limiter bunny_rate_limiter_t;

void bunny_rate_limiter_init(bunny_rate_limiter_t *limiter, double min_interval_sec);

/* Blocks the calling thread until min_interval_sec has elapsed since the
 * previous call (a no-op on the first call, and whenever min_interval_sec
 * is <= 0). */
void bunny_rate_limiter_wait(bunny_rate_limiter_t *limiter);

#endif /* BUNNY_COMMON_RATE_LIMIT_H */
