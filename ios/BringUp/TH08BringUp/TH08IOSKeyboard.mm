#include "TH08IOSKeyboard.h"

#include <array>
#include <mutex>

namespace {
std::array<uint8_t, 256> g_keyboardState = {};
std::mutex g_keyboardMutex;
}

extern "C" void TH08IOSSetKeyState(uint8_t virtualKeyCode, int isDown)
{
    std::lock_guard<std::mutex> lock(g_keyboardMutex);
    g_keyboardState[virtualKeyCode] = isDown ? 0x80 : 0x00;
}

extern "C" void TH08IOSClearKeyboardState(void)
{
    std::lock_guard<std::mutex> lock(g_keyboardMutex);
    g_keyboardState.fill(0);
}

extern "C" void TH08IOSGetKeyboardState(uint8_t *destination, size_t destinationLength)
{
    if (destination == nullptr || destinationLength == 0)
        return;

    std::lock_guard<std::mutex> lock(g_keyboardMutex);
    const size_t count = destinationLength < g_keyboardState.size()
        ? destinationLength
        : g_keyboardState.size();

    for (size_t index = 0; index < count; ++index)
        destination[index] = g_keyboardState[index];

    for (size_t index = count; index < destinationLength; ++index)
        destination[index] = 0;
}
