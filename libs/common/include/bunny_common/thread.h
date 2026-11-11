#ifndef BUNNY_COMMON_THREAD_H
#define BUNNY_COMMON_THREAD_H

#include <goblin/thread.h>

/* Cross-platform mutex/condition-variable/thread primitives -- MSVC has no
 * <pthread.h> at all (POSIX-only, no equivalent without a separate shim),
 * which this project only discovered once a real Windows CI build tried it
 * (every prior build was GCC/Clang locally, or dockcross/MinGW, which *does*
 * provide pthreads). Every pthread_* call site in bunny_core and the server
 * (db_mutex/sync_mutex, the scheduler/sync_worker background threads,
 * sync_status, the log ring buffer's mutex) goes through these instead, so
 * none of those files need their own #ifdef _WIN32.
 *
 * Thin `static inline` forwarding wrappers around GOBLIN's own goblin_thread
 * (vendored) -- keeps this header safe to include from any number of
 * translation units with no duplicate-symbol risk, same as before this was
 * built on GOBLIN; the one real implementation lives in goblin_impl.c via
 * GOBLIN_THREAD_IMPLEMENTATION. */

typedef goblin_mutex bunny_mutex_t;
typedef goblin_cond bunny_cond_t;
typedef goblin_thread bunny_thread_t;

static inline int bunny_mutex_init(bunny_mutex_t *mutex)
{
    return goblin_mutex_init(mutex);
}
static inline void bunny_mutex_destroy(bunny_mutex_t *mutex)
{
    goblin_mutex_destroy(mutex);
}
static inline void bunny_mutex_lock(bunny_mutex_t *mutex)
{
    goblin_mutex_lock(mutex);
}
static inline void bunny_mutex_unlock(bunny_mutex_t *mutex)
{
    goblin_mutex_unlock(mutex);
}

static inline int bunny_cond_init(bunny_cond_t *cond)
{
    return goblin_cond_init(cond);
}
static inline void bunny_cond_destroy(bunny_cond_t *cond)
{
    goblin_cond_destroy(cond);
}
static inline void bunny_cond_wait(bunny_cond_t *cond, bunny_mutex_t *mutex)
{
    goblin_cond_wait(cond, mutex);
}
static inline void bunny_cond_signal(bunny_cond_t *cond)
{
    goblin_cond_signal(cond);
}
static inline void bunny_cond_broadcast(bunny_cond_t *cond)
{
    goblin_cond_broadcast(cond);
}

static inline int bunny_thread_create(bunny_thread_t *thread, void *(*fn)(void *), void *arg)
{
    return goblin_thread_create(thread, fn, arg);
}
static inline int bunny_thread_join(bunny_thread_t thread)
{
    return goblin_thread_join(thread);
}

/* Releases the handle without waiting for the thread -- the thread itself
 * keeps running to completion regardless; this just gives up the ability
 * to later join/query it, which a detached thread's caller never needs to
 * do again. */
static inline void bunny_thread_detach(bunny_thread_t thread)
{
    goblin_thread_detach(thread);
}

/* POSIX sleep() takes whole seconds and needs <unistd.h>, neither of which
 * exist on MSVC -- used by the scheduler's poll loop and main.c's
 * shutdown-signal wait loop. */
static inline void bunny_sleep_seconds(unsigned int seconds)
{
    goblin_sleep_seconds(seconds);
}

#endif /* BUNNY_COMMON_THREAD_H */
