#include <windows.h>
#include <mmsystem.h>

#include <errno.h>
#include <glob.h>
#include <new>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
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

namespace
{
struct IOSFindHandle
{
    glob_t matches;
    size_t index;
};

BOOL CopyFindData(const IOSFindHandle *handle, WIN32_FIND_DATAA *data)
{
    if (handle == NULL || data == NULL || handle->index >= handle->matches.gl_pathc)
        return FALSE;

    memset(data, 0, sizeof(*data));
    const char *path = handle->matches.gl_pathv[handle->index];
    const char *name = strrchr(path, '/');
    name = name != NULL ? name + 1 : path;
    snprintf(data->cFileName, sizeof(data->cFileName), "%s", name);
    return TRUE;
}
} // namespace

BOOL DeleteFileA(LPCSTR path)
{
    return path != NULL && unlink(path) == 0 ? TRUE : FALSE;
}

HANDLE FindFirstFileA(LPCSTR pattern, WIN32_FIND_DATAA *data)
{
    if (pattern == NULL || data == NULL)
        return INVALID_HANDLE_VALUE;

    IOSFindHandle *handle = new (std::nothrow) IOSFindHandle();
    if (handle == NULL)
        return INVALID_HANDLE_VALUE;
    memset(&handle->matches, 0, sizeof(handle->matches));
    handle->index = 0;

    const int result = glob(pattern, 0, NULL, &handle->matches);
    if (result != 0 || handle->matches.gl_pathc == 0 || !CopyFindData(handle, data))
    {
        globfree(&handle->matches);
        delete handle;
        return INVALID_HANDLE_VALUE;
    }
    return static_cast<HANDLE>(handle);
}

BOOL FindNextFileA(HANDLE rawHandle, WIN32_FIND_DATAA *data)
{
    if (rawHandle == INVALID_HANDLE_VALUE || rawHandle == NULL || data == NULL)
        return FALSE;
    IOSFindHandle *handle = static_cast<IOSFindHandle *>(rawHandle);
    ++handle->index;
    return CopyFindData(handle, data);
}

BOOL FindClose(HANDLE rawHandle)
{
    if (rawHandle == INVALID_HANDLE_VALUE || rawHandle == NULL)
        return FALSE;
    IOSFindHandle *handle = static_cast<IOSFindHandle *>(rawHandle);
    globfree(&handle->matches);
    delete handle;
    return TRUE;
}

namespace
{
struct IOSThreadHandle
{
    pthread_t thread;
    pthread_mutex_t mutex;
    pthread_cond_t condition;
    LPTHREAD_START_ROUTINE startFunction;
    LPVOID parameter;
    DWORD threadId;
    DWORD exitCode;
    BOOL started;
    BOOL finished;
    uint32_t magic;
};

const uint32_t IOS_THREAD_HANDLE_MAGIC = 0x54483038;

void *ThreadEntry(void *rawHandle)
{
    IOSThreadHandle *handle = static_cast<IOSThreadHandle *>(rawHandle);
    const DWORD currentId = GetCurrentThreadId();

    pthread_mutex_lock(&handle->mutex);
    handle->threadId = currentId;
    handle->started = TRUE;
    pthread_cond_broadcast(&handle->condition);
    pthread_mutex_unlock(&handle->mutex);

    const DWORD exitCode = handle->startFunction(handle->parameter);

    pthread_mutex_lock(&handle->mutex);
    handle->exitCode = exitCode;
    handle->finished = TRUE;
    pthread_cond_broadcast(&handle->condition);
    pthread_mutex_unlock(&handle->mutex);
    return NULL;
}
} // namespace

HANDLE CreateThread(LPVOID, size_t stackSize, LPTHREAD_START_ROUTINE startFunction,
                    LPVOID parameter, DWORD creationFlags, LPDWORD threadId)
{
    if (startFunction == NULL || creationFlags != 0)
        return NULL;

    IOSThreadHandle *handle = new (std::nothrow) IOSThreadHandle();
    if (handle == NULL)
        return NULL;
    memset(handle, 0, sizeof(*handle));
    handle->startFunction = startFunction;
    handle->parameter = parameter;
    handle->magic = IOS_THREAD_HANDLE_MAGIC;
    pthread_mutex_init(&handle->mutex, NULL);
    pthread_cond_init(&handle->condition, NULL);

    pthread_attr_t attributes;
    pthread_attr_init(&attributes);
    if (stackSize != 0)
        pthread_attr_setstacksize(&attributes, stackSize);
    const int result = pthread_create(&handle->thread, &attributes, ThreadEntry, handle);
    pthread_attr_destroy(&attributes);
    if (result != 0)
    {
        pthread_cond_destroy(&handle->condition);
        pthread_mutex_destroy(&handle->mutex);
        delete handle;
        return NULL;
    }

    pthread_mutex_lock(&handle->mutex);
    while (!handle->started)
        pthread_cond_wait(&handle->condition, &handle->mutex);
    if (threadId != NULL)
        *threadId = handle->threadId;
    pthread_mutex_unlock(&handle->mutex);
    return static_cast<HANDLE>(handle);
}

DWORD WaitForSingleObject(HANDLE rawHandle, DWORD milliseconds)
{
    if (rawHandle == NULL || rawHandle == INVALID_HANDLE_VALUE)
        return 0xffffffffU;
    IOSThreadHandle *handle = static_cast<IOSThreadHandle *>(rawHandle);
    if (handle->magic != IOS_THREAD_HANDLE_MAGIC)
        return 0xffffffffU;

    pthread_mutex_lock(&handle->mutex);
    int result = 0;
    if (milliseconds == INFINITE)
    {
        while (!handle->finished && result == 0)
            result = pthread_cond_wait(&handle->condition, &handle->mutex);
    }
    else
    {
        struct timespec deadline;
        clock_gettime(CLOCK_REALTIME, &deadline);
        deadline.tv_sec += static_cast<time_t>(milliseconds / 1000U);
        deadline.tv_nsec += static_cast<long>((milliseconds % 1000U) * 1000000U);
        if (deadline.tv_nsec >= 1000000000L)
        {
            ++deadline.tv_sec;
            deadline.tv_nsec -= 1000000000L;
        }
        while (!handle->finished && result == 0)
            result = pthread_cond_timedwait(&handle->condition, &handle->mutex, &deadline);
    }
    const BOOL finished = handle->finished;
    pthread_mutex_unlock(&handle->mutex);
    if (finished)
        return WAIT_OBJECT_0;
    if (result == ETIMEDOUT)
        return WAIT_TIMEOUT;
    return 0xffffffffU;
}

BOOL CloseHandle(HANDLE rawHandle)
{
    if (rawHandle == NULL || rawHandle == INVALID_HANDLE_VALUE)
        return FALSE;
    IOSThreadHandle *handle = static_cast<IOSThreadHandle *>(rawHandle);
    if (handle->magic != IOS_THREAD_HANDLE_MAGIC)
        return FALSE;

    pthread_mutex_lock(&handle->mutex);
    const BOOL finished = handle->finished;
    pthread_mutex_unlock(&handle->mutex);
    if (!finished)
        return FALSE;

    if (pthread_join(handle->thread, NULL) != 0)
        return FALSE;
    handle->magic = 0;
    pthread_cond_destroy(&handle->condition);
    pthread_mutex_destroy(&handle->mutex);
    delete handle;
    return TRUE;
}

namespace
{
struct IOSTimerHandle
{
    UINT identifier;
    UINT delayMilliseconds;
    UINT flags;
    LPTIMECALLBACK callback;
    DWORD_PTR userData;
    pthread_t thread;
    pthread_mutex_t mutex;
    pthread_cond_t condition;
    BOOL stopRequested;
    BOOL finished;
    BOOL destroyOnExit;
};

pthread_mutex_t g_IOS_timerListMutex = PTHREAD_MUTEX_INITIALIZER;
IOSTimerHandle *g_IOS_timers[32] = {0};
UINT g_IOS_nextTimerIdentifier = 1;

void DestroyTimer(IOSTimerHandle *timer)
{
    pthread_cond_destroy(&timer->condition);
    pthread_mutex_destroy(&timer->mutex);
    delete timer;
}

void *TimerEntry(void *rawTimer)
{
    IOSTimerHandle *timer = static_cast<IOSTimerHandle *>(rawTimer);
    for (;;)
    {
        struct timespec deadline;
        clock_gettime(CLOCK_REALTIME, &deadline);
        deadline.tv_sec += static_cast<time_t>(timer->delayMilliseconds / 1000U);
        deadline.tv_nsec += static_cast<long>((timer->delayMilliseconds % 1000U) * 1000000U);
        if (deadline.tv_nsec >= 1000000000L)
        {
            ++deadline.tv_sec;
            deadline.tv_nsec -= 1000000000L;
        }

        pthread_mutex_lock(&timer->mutex);
        int result = 0;
        while (!timer->stopRequested && result == 0)
            result = pthread_cond_timedwait(&timer->condition, &timer->mutex, &deadline);
        const BOOL shouldStop = timer->stopRequested;
        pthread_mutex_unlock(&timer->mutex);

        if (shouldStop)
            break;
        if (result == ETIMEDOUT)
            timer->callback(timer->identifier, 0, timer->userData, 0, 0);
        if ((timer->flags & TIME_PERIODIC) == 0)
            break;
    }

    pthread_mutex_lock(&timer->mutex);
    timer->finished = TRUE;
    const BOOL destroyOnExit = timer->destroyOnExit;
    pthread_cond_broadcast(&timer->condition);
    pthread_mutex_unlock(&timer->mutex);
    if (destroyOnExit)
        DestroyTimer(timer);
    return NULL;
}
} // namespace

DWORD timeGetTime(void)
{
    LARGE_INTEGER counter;
    if (!QueryPerformanceCounter(&counter))
        return 0;
    return static_cast<DWORD>(counter.QuadPart / 1000000LL);
}

MMRESULT timeGetDevCaps(TIMECAPS *caps, UINT size)
{
    if (caps == NULL || size < sizeof(TIMECAPS))
        return 1;
    caps->wPeriodMin = 1;
    caps->wPeriodMax = 1000;
    return MMSYSERR_NOERROR;
}

MMRESULT timeBeginPeriod(UINT)
{
    return MMSYSERR_NOERROR;
}

MMRESULT timeEndPeriod(UINT)
{
    return MMSYSERR_NOERROR;
}

UINT timeSetEvent(UINT delay, UINT, LPTIMECALLBACK callback, DWORD_PTR userData, UINT flags)
{
    if (delay == 0 || callback == NULL)
        return 0;
    IOSTimerHandle *timer = new (std::nothrow) IOSTimerHandle();
    if (timer == NULL)
        return 0;
    memset(timer, 0, sizeof(*timer));
    timer->delayMilliseconds = delay;
    timer->flags = flags;
    timer->callback = callback;
    timer->userData = userData;
    pthread_mutex_init(&timer->mutex, NULL);
    pthread_cond_init(&timer->condition, NULL);

    pthread_mutex_lock(&g_IOS_timerListMutex);
    size_t slot = 32;
    for (size_t i = 0; i < 32; ++i)
    {
        if (g_IOS_timers[i] == NULL)
        {
            slot = i;
            break;
        }
    }
    if (slot == 32)
    {
        pthread_mutex_unlock(&g_IOS_timerListMutex);
        DestroyTimer(timer);
        return 0;
    }
    timer->identifier = g_IOS_nextTimerIdentifier++;
    if (timer->identifier == 0)
        timer->identifier = g_IOS_nextTimerIdentifier++;
    g_IOS_timers[slot] = timer;
    pthread_mutex_unlock(&g_IOS_timerListMutex);

    if (pthread_create(&timer->thread, NULL, TimerEntry, timer) != 0)
    {
        pthread_mutex_lock(&g_IOS_timerListMutex);
        g_IOS_timers[slot] = NULL;
        pthread_mutex_unlock(&g_IOS_timerListMutex);
        DestroyTimer(timer);
        return 0;
    }
    return timer->identifier;
}

MMRESULT timeKillEvent(UINT identifier)
{
    IOSTimerHandle *timer = NULL;
    pthread_mutex_lock(&g_IOS_timerListMutex);
    for (size_t i = 0; i < 32; ++i)
    {
        if (g_IOS_timers[i] != NULL && g_IOS_timers[i]->identifier == identifier)
        {
            timer = g_IOS_timers[i];
            g_IOS_timers[i] = NULL;
            break;
        }
    }
    pthread_mutex_unlock(&g_IOS_timerListMutex);
    if (timer == NULL)
        return 1;

    pthread_mutex_lock(&timer->mutex);
    timer->stopRequested = TRUE;
    const BOOL calledFromTimerThread = pthread_equal(pthread_self(), timer->thread);
    if (calledFromTimerThread)
        timer->destroyOnExit = TRUE;
    pthread_cond_broadcast(&timer->condition);
    pthread_mutex_unlock(&timer->mutex);

    if (!calledFromTimerThread)
    {
        if (pthread_join(timer->thread, NULL) != 0)
            return 1;
        DestroyTimer(timer);
    }
    return MMSYSERR_NOERROR;
}

MMRESULT midiOutOpen(HMIDIOUT *output, UINT, DWORD_PTR, DWORD_PTR, DWORD)
{
    if (output != NULL)
        *output = NULL;
    return 1;
}
MMRESULT midiOutClose(HMIDIOUT) { return 1; }
MMRESULT midiOutReset(HMIDIOUT) { return 1; }
MMRESULT midiOutPrepareHeader(HMIDIOUT, LPMIDIHDR, UINT) { return 1; }
MMRESULT midiOutUnprepareHeader(HMIDIOUT, LPMIDIHDR, UINT) { return 1; }
MMRESULT midiOutLongMsg(HMIDIOUT, LPMIDIHDR, UINT) { return 1; }
MMRESULT midiOutShortMsg(HMIDIOUT, DWORD) { return 1; }
