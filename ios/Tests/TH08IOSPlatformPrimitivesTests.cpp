#include <windows.h>

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
    struct ThreadArguments
    {
        volatile DWORD *result;
    };
    ThreadArguments arguments = {&threadResult};
    DWORD createdThreadId = 0;
    HANDLE thread = CreateThread(NULL, 0,
        [](LPVOID raw) -> DWORD {
            ThreadArguments *args = static_cast<ThreadArguments *>(raw);
            Sleep(20);
            *args->result = 7;
            return 7;
        },
        &arguments, 0, &createdThreadId);
    assert(thread != NULL);
    assert(createdThreadId != 0);
    assert(WaitForSingleObject(thread, 1) == WAIT_TIMEOUT);
    assert(WaitForSingleObject(thread, INFINITE) == WAIT_OBJECT_0);
    assert(threadResult == 7);
    assert(CloseHandle(thread));
    return 0;
}
