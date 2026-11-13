#pragma once

// The game sources still use the original Win32/DirectX type surface. For the
// first iOS compile checkpoint, reuse the repository's portable declarations
// while deliberately not enabling the SDL/Linux runtime implementation.
#ifndef TH08_MODERN_IOS
#define TH08_MODERN_IOS 1
#endif
#ifndef TH08_MODERN_PORT
#define TH08_MODERN_PORT 1
#endif

#include <strings.h>
#include <windows.h>
#include <mmreg.h>
#include <mmsystem.h>
#include <d3d8.h>
#include <d3dx8.h>
#include <dsound.h>
#include <dinput.h>
#include <winnls32.h>

#include "TH08IOSKeyboard.h"

#ifndef _snwprintf
#define _snwprintf swprintf
#endif
#ifndef D3D_WRAPPER
#define D3D_WRAPPER 0
#endif

#define VK_SHIFT 0x10
#define VK_CONTROL 0x11
#define VK_RETURN 0x0d
#define VK_ESCAPE 0x1b
#define VK_HOME 0x24
#define VK_LEFT 0x25
#define VK_UP 0x26
#define VK_RIGHT 0x27
#define VK_DOWN 0x28
#define VK_NUMPAD1 0x61
#define VK_NUMPAD2 0x62
#define VK_NUMPAD3 0x63
#define VK_NUMPAD4 0x64
#define VK_NUMPAD6 0x66
#define VK_NUMPAD7 0x67
#define VK_NUMPAD8 0x68
#define VK_NUMPAD9 0x69

#define TRANSPARENT 1
#define BI_RGB 0
#define DIB_RGB_COLORS 0
#define FW_NORMAL 400
#define FW_BOLD 700
#define FW_SEMIBOLD 600
#define DEFAULT_CHARSET 1
#define SHIFTJIS_CHARSET 128
#define OUT_DEFAULT_PRECIS 0
#define CLIP_DEFAULT_PRECIS 0
#define ANTIALIASED_QUALITY 4
#define DEFAULT_PITCH 0
#define FIXED_PITCH 1
#define FF_ROMAN 16
