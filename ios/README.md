# iOS port

This directory contains the native iOS host application and the platform
adapters being developed for the original TH08 engine.

The current checkpoint provides a native bring-up shell, paired import of the
user's original archives, bounded decompression and structural validation of
the complete PBG file table, and a physical-keyboard state buffer indexed by
Win32 virtual-key codes. Import validates the retail PBG signature, decrypts
the fixed-size header and compressed file table, checks the declared output
size, and verifies each entry name and payload offset before replacing the
stored pair. Individual asset payloads are still decompressed by the game
engine at load time. An iOS-only compile-time path now bypasses DirectInput
and reads the UIKit keyboard buffer from `Controller::GetInput`; no iOS game
target currently compiles or runs that path.

## Renderer foundation

`BringUp/Renderer/TH08IOSGLRenderer` is the first native OpenGL ES 2 renderer
module. It compiles and links explicit vertex/fragment shaders, accepts
interleaved position/UV/RGBA vertices, draws primitive arrays, uploads RGBA8
textures, applies explicit blend/depth/viewport state, accepts a column-major\n4×4 transform matrix, and implements fragment-shader alpha comparison for\nDirect3D 8 alpha-test modes. It is compiled into
the bring-up target so both Simulator and device SDK builds validate the iOS
graphics API integration.

This is only a renderer foundation, not a Direct3D 8 replacement. It does not
yet implement the original engine's matrix stack and D3D8 transform/viewport
conventions, transformed/lit vertex formats, fog semantics, texture-stage
combiner behavior, render targets, readback, full texture formats, or resource
lifecycle. The game engine does not call it yet. The original
Win32/Direct3D 8 entry point and SDL2/desktop-OpenGL runtime still need an iOS
platform implementation.

## Bring-up app

The XcodeGen project in `BringUp/project.yml` builds a SwiftUI app. It imports:

- `th08.dat`
- `thbgm.dat`

Both files must be selected together. They are staged under
Application Support/TH08Data and replace the previous pair only after both
copies succeed. Game archives are never committed to this repository.

The UIKit keyboard responder captures external keyboard presses/releases and
maps the TH08 movement, shot, bomb, confirm, Escape, Control, and Shift keys to
Win32 virtual-key indices. This matches the index convention used by the
engine's `GetKeyboardState` input path when no DirectInput keyboard device is
present; it is not a DirectInput scan-code table. There are no touch controls.
The C ABI in `TH08IOSKeyboard.h` exposes the 256-byte key state for the future
engine adapter.

## Build

On macOS with Xcode and XcodeGen installed:

```sh
cd ios/BringUp
xcodegen generate
xcodebuild -project TH08BringUp.xcodeproj \
  -scheme TH08BringUp -sdk iphonesimulator \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

The GitHub Actions workflow `.github/workflows/ios-bringup.yml` performs an
unsigned Simulator build and an unsigned generic iOS device build on a macOS
runner. These are compile checks only; an unsigned build is not an installable,
signed IPA.

## Remaining engine integration

1. Introduce an iOS application entry point and lifecycle-aware frame loop.
2. Replace the Win32 window/message-pump boundary without changing reconstructed
   game logic or its exactness evidence.
3. Extend the ES2 renderer to match Direct3D 8 state/resource behavior and
   validate it against deterministic reference captures.
4. Connect the renderer and keyboard-state ABI to the game's actual input and
   frame loop.
5. Port audio, timing, save/config paths, focus handling, and full archive
   loading, including file-table decompression and entry validation.
6. Run the original game with user-imported archives on a physical iPhone and
   verify gameplay, audio, suspend/resume, and frame pacing. The synthetic PBG
   parser tests run in the iOS workflow on Linux; the keyboard bridge and Xcode
   builds run on macOS.

Do not add a nominal Apple CMake target that links stubs in place of platform
services. Keep the original Windows/Linux targets and reconstruction sources
unchanged while the iOS boundary is developed.
