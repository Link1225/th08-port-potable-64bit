#ifndef TH08IOSKeyboard_h
#define TH08IOSKeyboard_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Uses Win32 virtual-key indices because Controller::GetInput reads the
// GetKeyboardState-compatible branch when no DirectInput device is present.
void TH08IOSSetKeyState(uint8_t virtualKeyCode, int isDown);
void TH08IOSClearKeyboardState(void);
void TH08IOSGetKeyboardState(uint8_t *destination, size_t destinationLength);

#ifdef __cplusplus
}
#endif

#endif
