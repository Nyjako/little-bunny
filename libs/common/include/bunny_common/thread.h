#ifndef BUNNY_COMMON_THREAD_H
#define BUNNY_COMMON_THREAD_H

/* Cross-platform mutex/condition-variable/thread primitives -- MSVC has no
 * <pthread.h> at all (POSIX-only, no equivalent without a separate shim),
 * which this project only discovered once a real Windows CI build tried it
 * (every prior build was GCC/Clang locally, or dockcross/MinGW, which *does*
 * provide pthreads). Every pthread_* call site in bunny_core and the server
 * (db_mutex/sync_mutex, the scheduler/sync_worker background threads,
 * sync_status, the log ring buffer's mutex) goes through these instead, so
 * none of those files need their own #ifdef _WIN32. All functions are
 * `static inline` -- safe to include from multiple translation units/static
 * libraries with no duplicate-symbol risk, same reasoning as every other
 * static inline helper in this codebase. */

#ifdef _WIN32

#include <stdlib.h>
#include <windows.h>

typedef CRITICAL_SECTION bunny_mutex_t;
typedef CONDITION_VARIABLE bunny_cond_t;
typedef HANDLE bunny_thread_t;

static inline int bunny_mutex_init(bunny_mutex_t *mutex)
{
    InitializeCriticalSection(mutex);
    return 0;
}
static inline void bunny_mutex_destroy(bunny_mutex_t *mutex) { DeleteCriticalSection(mutex); }
static inline void bunny_mutex_lock(bunny_mutex_t *mutex) { EnterCriticalSection(mutex); }
static inline void bunny_mutex_unlock(bunny_mutex_t *mutex) { LeaveCriticalSection(mutex); }

static inline int bunny_cond_init(bunny_cond_t *cond)
{
    InitializeConditionVariable(cond);
    return 0;
}
static inline void bunny_cond_destroy(bunny_cond_t *cond) { (void)cond; /* no destruction needed on Windows */ }
static inline void bunny_cond_wait(bunny_cond_t *cond, bunny_mutex_t *mutex) { SleepConditionVariableCS(cond, mutex, INFINITE); }
static inline void bunny_cond_signal(bunny_cond_t *cond) { WakeConditionVariable(cond); }
static inline void bunny_cond_broadcast(bunny_cond_t *cond) { WakeAllConditionVariable(cond); }

typedef struct
{
    void *(*fn)(void *);
    void *arg;
} bunny_thread_start_t;

/* CreateThread needs a DWORD WINAPI(LPVOID) proc, not pthread's void*(void*)
 * -- a plain function-pointer cast between the two is technically undefined
 * behavior (differing return type), so this trampolines through a real
 * matching signature instead of relying on it happening to work. */
static inline DWORD WINAPI bunny_thread_trampoline(LPVOID param)
{
    bunny_thread_start_t *start = (bunny_thread_start_t *)param;
    void *(*fn)(void *) = start->fn;
    void *arg = start->arg;
    free(start);
    fn(arg);
    return 0;
}

static inline int bunny_thread_create(bunny_thread_t *thread, void *(*fn)(void *), void *arg)
{
    bunny_thread_start_t *start = malloc(sizeof(*start));
    if (!start) {
        return -1;
    }
    start->fn = fn;
    start->arg = arg;
    *thread = CreateThread(NULL, 0, bunny_thread_trampoline, start, 0, NULL);
    if (!*thread) {
        free(start);
        return -1;
    }
    return 0;
}

static inline int bunny_thread_join(bunny_thread_t thread)
{
    WaitForSingleObject(thread, INFINITE);
    CloseHandle(thread);
    return 0;
}

#else

#include <pthread.h>

typedef pthread_mutex_t bunny_mutex_t;
typedef pthread_cond_t bunny_cond_t;
typedef pthread_t bunny_thread_t;

static inline int bunny_mutex_init(bunny_mutex_t *mutex) { return pthread_mutex_init(mutex, NULL); }
static inline void bunny_mutex_destroy(bunny_mutex_t *mutex) { pthread_mutex_destroy(mutex); }
static inline void bunny_mutex_lock(bunny_mutex_t *mutex) { pthread_mutex_lock(mutex); }
static inline void bunny_mutex_unlock(bunny_mutex_t *mutex) { pthread_mutex_unlock(mutex); }

static inline int bunny_cond_init(bunny_cond_t *cond) { return pthread_cond_init(cond, NULL); }
static inline void bunny_cond_destroy(bunny_cond_t *cond) { pthread_cond_destroy(cond); }
static inline void bunny_cond_wait(bunny_cond_t *cond, bunny_mutex_t *mutex) { pthread_cond_wait(cond, mutex); }
static inline void bunny_cond_signal(bunny_cond_t *cond) { pthread_cond_signal(cond); }
static inline void bunny_cond_broadcast(bunny_cond_t *cond) { pthread_cond_broadcast(cond); }

static inline int bunny_thread_create(bunny_thread_t *thread, void *(*fn)(void *), void *arg) { return pthread_create(thread, NULL, fn, arg); }
static inline int bunny_thread_join(bunny_thread_t thread) { return pthread_join(thread, NULL); }

#endif

/* POSIX sleep() takes whole seconds and needs <unistd.h>, neither of which
 * exist on MSVC -- Sleep() (note the capital S) is the Win32 equivalent,
 * taking milliseconds instead. Used by the scheduler's poll loop and
 * main.c's shutdown-signal wait loop. */
#ifdef _WIN32
static inline void bunny_sleep_seconds(unsigned int seconds) { Sleep(seconds * 1000); }
#else
#include <unistd.h>
static inline void bunny_sleep_seconds(unsigned int seconds) { sleep(seconds); }
#endif

#endif /* BUNNY_COMMON_THREAD_H */
