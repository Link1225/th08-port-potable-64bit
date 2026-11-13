#include <windows.h>
#include <mmsystem.h>

#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <string.h>

struct WorkerState
{
    CRITICAL_SECTION *section;
    volatile int *counter;
};

static void *IncrementWorker(void *argument)
{
    WorkerState *state = static_cast<WorkerState *>(argument);
    for (int i = 0; i < 10000; ++i)
    {
        EnterCriticalSection(state->section);
        ++(*state->counter);
        LeaveCriticalSection(state->section);
    }
    return NULL;
}

DWORD timeGetTime(void);

struct TimerCounter
{
    pthread_mutex_t mutex;
    pthread_cond_t condition;
    UINT count;
};

static UINT TimerCallback(UINT, UINT, DWORD_PTR userData, DWORD_PTR, DWORD_PTR)
{
    TimerCounter *counter = reinterpret_cast<TimerCounter *>(userData);
    pthread_mutex_lock(&counter->mutex);
    ++counter->count;
    pthread_cond_broadcast(&counter->condition);
    pthread_mutex_unlock(&counter->mutex);
    return 0;
}

struct ThreadArguments
{
    volatile DWORD *result;
    pthread_mutex_t mutex;
    pthread_cond_t condition;
    BOOL release;
};

static DWORD WINAPI ThreadWorker(LPVOID raw)
{
    ThreadArguments *arguments = static_cast<ThreadArguments *>(raw);
    pthread_mutex_lock(&arguments->mutex);
    while (!arguments->release)
        pthread_cond_wait(&arguments->condition, &arguments->mutex);
    pthread_mutex_unlock(&arguments->mutex);
    *arguments->result = 7;
    return 7;
}

int main()
{
    CRITICAL_SECTION section;
    InitializeCriticalSection(&section);
    EnterCriticalSection(&section);
    EnterCriticalSection(&section);
    LeaveCriticalSection(&section);
    LeaveCriticalSection(&section);

    volatile int counter = 0;
    WorkerState state = {&section, &counter};
    pthread_t first;
    pthread_t second;
    assert(pthread_create(&first, NULL, IncrementWorker, &state) == 0);
    assert(pthread_create(&second, NULL, IncrementWorker, &state) == 0);
    assert(pthread_join(first, NULL) == 0);
    assert(pthread_join(second, NULL) == 0);
    assert(counter == 20000);
    DeleteCriticalSection(&section);

    LARGE_INTEGER frequency;
    LARGE_INTEGER start;
    LARGE_INTEGER finish;
    assert(QueryPerformanceFrequency(&frequency));
    assert(frequency.QuadPart == 1000000000LL);
    assert(QueryPerformanceCounter(&start));
    Sleep(2);
    assert(QueryPerformanceCounter(&finish));
    assert(finish.QuadPart > start.QuadPart);
    assert(GetCurrentThreadId() != 0);

    unsigned char *memory = static_cast<unsigned char *>(GlobalAlloc(LPTR, 16));
    assert(memory != NULL);
    for (int i = 0; i < 16; ++i)
        assert(memory[i] == 0);
    assert(GlobalFree(memory) == NULL);

    char directory[] = "/tmp/th08-ios-find-XXXXXX";
    assert(mkdtemp(directory) != NULL);
    char firstPath[512];
    char secondPath[512];
    char ignoredPath[512];
    snprintf(firstPath, sizeof(firstPath), "%s/score_1.260101.bak", directory);
    snprintf(secondPath, sizeof(secondPath), "%s/score_1.260102.bak", directory);
    snprintf(ignoredPath, sizeof(ignoredPath), "%s/other.dat", directory);
    FILE *first = fopen(firstPath, "wb");
    FILE *second = fopen(secondPath, "wb");
    FILE *ignored = fopen(ignoredPath, "wb");
    assert(first != NULL && second != NULL && ignored != NULL);
    fclose(first);
    fclose(second);
    fclose(ignored);

    char pattern[512];
    snprintf(pattern, sizeof(pattern), "%s/score_1.??????.bak", directory);
    WIN32_FIND_DATAA findData;
    HANDLE findHandle = FindFirstFileA(pattern, &findData);
    assert(findHandle != INVALID_HANDLE_VALUE);
    int found = 1;
    while (FindNextFileA(findHandle, &findData))
        ++found;
    assert(found == 2);
    assert(FindClose(findHandle));
    assert(DeleteFileA(firstPath));
    assert(DeleteFileA(secondPath));
    assert(DeleteFileA(ignoredPath));
    assert(rmdir(directory) == 0);
    assert(FindClose(INVALID_HANDLE_VALUE) == FALSE);

    volatile DWORD threadResult = 0;
    ThreadArguments arguments;
    arguments.result = &threadResult;
    arguments.release = FALSE;
    assert(pthread_mutex_init(&arguments.mutex, NULL) == 0);
    assert(pthread_cond_init(&arguments.condition, NULL) == 0);
    DWORD createdThreadId = 0;
    HANDLE thread = CreateThread(NULL, 0, ThreadWorker,
                                 &arguments, 0, &createdThreadId);
    assert(thread != NULL);
    assert(createdThreadId != 0);
    assert(WaitForSingleObject(thread, 1) == WAIT_TIMEOUT);
    pthread_mutex_lock(&arguments.mutex);
    arguments.release = TRUE;
    pthread_cond_broadcast(&arguments.condition);
    pthread_mutex_unlock(&arguments.mutex);
    assert(WaitForSingleObject(thread, INFINITE) == WAIT_OBJECT_0);
    assert(threadResult == 7);
    assert(CloseHandle(thread));
    pthread_cond_destroy(&arguments.condition);
    pthread_mutex_destroy(&arguments.mutex);

    TIMECAPS capabilities;
    assert(timeGetDevCaps(&capabilities, sizeof(capabilities)) == MMSYSERR_NOERROR);
    assert(capabilities.wPeriodMin == 1);
    assert(timeBeginPeriod(1) == MMSYSERR_NOERROR);
    const DWORD timerStart = timeGetTime();
    Sleep(3);
    assert(timeGetTime() >= timerStart);
    assert(timeEndPeriod(1) == MMSYSERR_NOERROR);

    TimerCounter timerCounter;
    timerCounter.count = 0;
    assert(pthread_mutex_init(&timerCounter.mutex, NULL) == 0);
    assert(pthread_cond_init(&timerCounter.condition, NULL) == 0);
    const UINT timerId = timeSetEvent(5, 1, TimerCallback,
                                      reinterpret_cast<DWORD_PTR>(&timerCounter),
                                      TIME_PERIODIC);
    assert(timerId != 0);
    pthread_mutex_lock(&timerCounter.mutex);
    while (timerCounter.count < 3)
        pthread_cond_wait(&timerCounter.condition, &timerCounter.mutex);
    pthread_mutex_unlock(&timerCounter.mutex);
    assert(timeKillEvent(timerId) == MMSYSERR_NOERROR);
    assert(timerCounter.count >= 3);
    pthread_cond_destroy(&timerCounter.condition);
    pthread_mutex_destroy(&timerCounter.mutex);

    HMIDIOUT midiHandle = reinterpret_cast<HMIDIOUT>(1);
    assert(midiOutOpen(&midiHandle, MIDI_MAPPER, 0, 0, 0) != MMSYSERR_NOERROR);
    assert(midiHandle == NULL);
    return 0;
}
