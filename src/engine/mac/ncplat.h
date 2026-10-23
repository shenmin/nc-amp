/* SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (C) 2026 Shen Min
 *
 * ncplat.h - the few Win32 primitives ncaudio.c uses (critical sections, events, threads,
 * tick count, interlocked operations, environment), implemented on POSIX threads for macOS.
 * Only included when _WIN32 is not defined; the Windows build uses the real ones.
 */
#ifndef NCPLAT_H
#define NCPLAT_H

#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <errno.h>
#include <unistd.h>

typedef int32_t  LONG;
typedef uint32_t DWORD;
typedef uint64_t ULONGLONG;
typedef void    *HANDLE;
typedef void    *LPVOID;
typedef int      BOOL;
#define WINAPI
#define TRUE 1
#define FALSE 0
#define WAIT_OBJECT_0 0
#define WAIT_TIMEOUT  258
#define INFINITE      0xFFFFFFFFu

typedef pthread_mutex_t CRITICAL_SECTION;
#define InitializeCriticalSection(p) do { pthread_mutexattr_t a_; pthread_mutexattr_init(&a_); \
    pthread_mutexattr_settype(&a_, PTHREAD_MUTEX_RECURSIVE); pthread_mutex_init((p), &a_); pthread_mutexattr_destroy(&a_); } while (0)
#define EnterCriticalSection(p)      pthread_mutex_lock(p)
#define LeaveCriticalSection(p)      pthread_mutex_unlock(p)
#define TryEnterCriticalSection(p)   (pthread_mutex_trylock(p) == 0)

#define InterlockedIncrement(p)          (__sync_add_and_fetch((p), 1))
#define InterlockedExchange(p, v)        (__sync_lock_test_and_set((p), (v)))

static inline ULONGLONG GetTickCount64(void)
{
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (ULONGLONG)ts.tv_sec * 1000u + (ULONGLONG)(ts.tv_nsec / 1000000);
}
static inline void Sleep(DWORD ms) { usleep((useconds_t)ms * 1000u); }
static inline void SwitchToThread(void) { sched_yield(); }

/* events (auto-reset or manual-reset) and thread handles share one object type */
typedef struct nc_obj {
    pthread_mutex_t m; pthread_cond_t c;
    int signaled, manual, detached;
    pthread_t th; int isThread;
    DWORD (*fn)(LPVOID); LPVOID arg;
} nc_obj;

static inline HANDLE CreateEventA(void *attr, BOOL manual, BOOL initial, const char *name)
{
    nc_obj *o = (nc_obj *)calloc(1, sizeof *o); (void)attr; (void)name;
    if (!o) return NULL;
    pthread_mutex_init(&o->m, NULL); pthread_cond_init(&o->c, NULL);
    o->manual = manual; o->signaled = initial;
    return o;
}
static inline BOOL SetEvent(HANDLE h)
{
    nc_obj *o = (nc_obj *)h;
    pthread_mutex_lock(&o->m); o->signaled = 1; pthread_cond_broadcast(&o->c); pthread_mutex_unlock(&o->m);
    return TRUE;
}
static inline DWORD WaitForSingleObject(HANDLE h, DWORD ms)
{
    nc_obj *o = (nc_obj *)h; int rc = 0; struct timespec ts;
    pthread_mutex_lock(&o->m);
    if (ms != INFINITE) {
        clock_gettime(CLOCK_REALTIME, &ts);
        ts.tv_sec += ms / 1000; ts.tv_nsec += (long)(ms % 1000) * 1000000L;
        if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }
    }
    while (!o->signaled && rc == 0)
        rc = (ms == INFINITE) ? pthread_cond_wait(&o->c, &o->m) : pthread_cond_timedwait(&o->c, &o->m, &ts);
    if (o->signaled && !o->manual) o->signaled = 0;
    rc = o->signaled || rc == 0 ? WAIT_OBJECT_0 : WAIT_TIMEOUT;
    pthread_mutex_unlock(&o->m);
    return (DWORD)rc;
}
static inline void *nc_thread_tramp(void *p)
{
    nc_obj *o = (nc_obj *)p;
    o->fn(o->arg);
    pthread_mutex_lock(&o->m); o->signaled = 1; o->manual = 1; pthread_cond_broadcast(&o->c);
    if (o->detached) { pthread_mutex_unlock(&o->m); free(o); return NULL; }
    pthread_mutex_unlock(&o->m);
    return NULL;
}
static inline HANDLE CreateThread(void *attr, size_t stack, DWORD (*fn)(LPVOID), LPVOID arg, DWORD flags, DWORD *id)
{
    nc_obj *o = (nc_obj *)calloc(1, sizeof *o); (void)attr; (void)stack; (void)flags; (void)id;
    if (!o) return NULL;
    pthread_mutex_init(&o->m, NULL); pthread_cond_init(&o->c, NULL);
    o->isThread = 1; o->manual = 1; o->fn = fn; o->arg = arg;
    if (pthread_create(&o->th, NULL, nc_thread_tramp, o) != 0) { free(o); return NULL; }
    return o;
}
static inline BOOL CloseHandle(HANDLE h)
{
    nc_obj *o = (nc_obj *)h;
    if (!o) return FALSE;
    if (o->isThread) {
        pthread_mutex_lock(&o->m);
        if (!o->signaled) { o->detached = 1; pthread_detach(o->th); pthread_mutex_unlock(&o->m); return TRUE; }  /* still running: it frees itself */
        pthread_mutex_unlock(&o->m);
        pthread_join(o->th, NULL);
    }
    free(o);
    return TRUE;
}
static inline DWORD GetCurrentThreadId(void) { return (DWORD)(uintptr_t)pthread_self(); }
static inline DWORD GetEnvironmentVariableA(const char *name, char *buf, DWORD cap)
{
    const char *v = getenv(name); size_t n;
    if (!v) { if (cap) buf[0] = 0; return 0; }
    n = strlen(v); if (n >= cap) n = cap - 1;
    memcpy(buf, v, n); buf[n] = 0;
    return (DWORD)n;
}
#endif
