#include "../BringUp/TH08BringUp/TH08IOSKeyboard.h"

#include <array>
#include <cassert>
#include <cstdint>

int main()
{
    std::array<std::uint8_t, 256> state{};

    TH08IOSClearKeyboardState();
    TH08IOSSetKeyState(0x5A, 1); // VK_Z
    TH08IOSSetKeyState(0x25, 1); // VK_LEFT
    TH08IOSGetKeyboardState(state.data(), state.size());

    assert(state[0x5A] == 0x80);
    assert(state[0x25] == 0x80);
    assert(state[0x58] == 0x00);

    TH08IOSSetKeyState(0x5A, 0);
    TH08IOSGetKeyboardState(state.data(), state.size());
    assert(state[0x5A] == 0x00);
    assert(state[0x25] == 0x80);

    std::array<std::uint8_t, 4> shortState{};
    TH08IOSGetKeyboardState(shortState.data(), shortState.size());
    assert(shortState[0] == 0x00);

    TH08IOSClearKeyboardState();
    TH08IOSGetKeyboardState(state.data(), state.size());
    for (std::uint8_t keyState : state)
        assert(keyState == 0x00);

    // The API zero-fills any caller-provided tail beyond the 256-key state.
    std::array<std::uint8_t, 260> oversizedState{};
    oversizedState.fill(0xFF);
    TH08IOSGetKeyboardState(oversizedState.data(), oversizedState.size());
    for (std::size_t index = 256; index < oversizedState.size(); ++index)
        assert(oversizedState[index] == 0x00);

    return 0;
}
