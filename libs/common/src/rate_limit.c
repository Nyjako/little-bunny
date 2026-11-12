#include "bunny_common/rate_limit.h"

void bunny_rate_limiter_init(bunny_rate_limiter_t *limiter, double min_interval_sec)
{
    goblin_rate_limiter_init(limiter, min_interval_sec);
}

void bunny_rate_limiter_wait(bunny_rate_limiter_t *limiter)
{
    goblin_rate_limiter_wait(limiter);
}
