#ifndef BUNNY_COMMON_RATE_LIMIT_H
#define BUNNY_COMMON_RATE_LIMIT_H

#include <stdbool.h>

#include <goblin/high_res_timer.h>

/* Shared by libe621/libinkbunny's client.c, both of which pace outgoing
 * requests to min_request_interval_sec apart -- was previously duplicated
 * in each as POSIX clock_gettime(CLOCK_MONOTONIC, ...)/nanosleep, which
 * doesn't exist on MSVC (no CLOCK_MONOTONIC, no nanosleep); built on
 * GOBLIN's own cross-platform goblin_timer instead. */
typedef struct
{
    double min_interval_sec;
    goblin_timer last_request_time;
    bool has_last_request_time;
} bunny_rate_limiter_t;

void bunny_rate_limiter_init(bunny_rate_limiter_t *limiter, double min_interval_sec);

/* Blocks the calling thread until min_interval_sec has elapsed since the
 * previous call (a no-op on the first call, and whenever min_interval_sec
 * is <= 0). */
void bunny_rate_limiter_wait(bunny_rate_limiter_t *limiter);

#endif /* BUNNY_COMMON_RATE_LIMIT_H */
