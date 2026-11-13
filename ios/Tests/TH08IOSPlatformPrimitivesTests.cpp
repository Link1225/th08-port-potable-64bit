#include <windows.h>

#include <assert.h>
#include <pthread.h>
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
    return 0;
}
