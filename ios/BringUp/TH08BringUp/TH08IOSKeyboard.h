#ifndef TH08IOSKeyboard_h
#define TH08IOSKeyboard_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void TH08IOSSetKeyState(uint8_t directInputScanCode, int isDown);
void TH08IOSClearKeyboardState(void);
void TH08IOSGetKeyboardState(uint8_t *destination, size_t destinationLength);

#ifdef __cplusplus
}
#endif

#endif
