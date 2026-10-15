#include "bunny_common/rate_limit.h"

#ifdef _WIN32
#include <windows.h>
#else
#include <time.h>
#endif

void bunny_rate_limiter_init(bunny_rate_limiter_t *limiter, double min_interval_sec)
{
    limiter->min_interval_sec = min_interval_sec;
    limiter->has_last_request_time = false;
}

void bunny_rate_limiter_wait(bunny_rate_limiter_t *limiter)
{
    if (limiter->min_interval_sec <= 0) {
        return;
    }

    if (limiter->has_last_request_time) {
        double elapsed = goblin_timer_elapsed_seconds(&limiter->last_request_time);
        double remaining = limiter->min_interval_sec - elapsed;
        if (remaining > 0) {
#ifdef _WIN32
            Sleep((DWORD)(remaining * 1000.0));
#else
            struct timespec sleep_time;
            sleep_time.tv_sec = (time_t)remaining;
            sleep_time.tv_nsec = (long)((remaining - (double)sleep_time.tv_sec) * 1e9);
            nanosleep(&sleep_time, NULL);
#endif
        }
    }

    goblin_timer_start(&limiter->last_request_time);
    limiter->has_last_request_time = true;
}
