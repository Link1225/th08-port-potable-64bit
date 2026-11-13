#include <windows.h>

#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

void Sleep(DWORD milliseconds)
{
    struct timespec remaining;
    remaining.tv_sec = static_cast<time_t>(milliseconds / 1000U);
    remaining.tv_nsec = static_cast<long>((milliseconds % 1000U) * 1000000U);
    while (nanosleep(&remaining, &remaining) != 0 && errno == EINTR)
    {
    }
}

BOOL QueryPerformanceFrequency(LARGE_INTEGER *frequency)
{
    if (frequency == NULL)
        return FALSE;
    frequency->QuadPart = 1000000000LL;
    return TRUE;
}

BOOL QueryPerformanceCounter(LARGE_INTEGER *counter)
{
    if (counter == NULL)
        return FALSE;
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
        return FALSE;
    counter->QuadPart = static_cast<long long>(now.tv_sec) * 1000000000LL + now.tv_nsec;
    return TRUE;
}

DWORD GetCurrentThreadId(void)
{
    return static_cast<DWORD>(reinterpret_cast<uintptr_t>(pthread_self()));
}

void InitializeCriticalSection(CRITICAL_SECTION *section)
{
    if (section == NULL)
        return;

    pthread_mutexattr_t attributes;
    if (pthread_mutexattr_init(&attributes) == 0)
    {
        pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(section, &attributes);
        pthread_mutexattr_destroy(&attributes);
    }
    else
    {
        pthread_mutex_init(section, NULL);
    }
}

void DeleteCriticalSection(CRITICAL_SECTION *section)
{
    if (section != NULL)
        pthread_mutex_destroy(section);
}

void EnterCriticalSection(CRITICAL_SECTION *section)
{
    if (section != NULL)
        pthread_mutex_lock(section);
}

void LeaveCriticalSection(CRITICAL_SECTION *section)
{
    if (section != NULL)
        pthread_mutex_unlock(section);
}

HGLOBAL GlobalAlloc(UINT flags, size_t bytes)
{
    if ((flags & LPTR) != 0)
        return calloc(1, bytes);
    return malloc(bytes);
}

HGLOBAL GlobalFree(HGLOBAL memory)
{
    free(memory);
    return NULL;
}
