# iOS port

This directory contains the native iOS host application and the platform
adapters being developed for the original TH08 engine.

The current checkpoint provides a native bring-up shell, paired import of the
user's original archives with full file-table structural validation, and a
physical-keyboard state buffer indexed by Win32 virtual-key codes. Import checks the retail PBG signature, decrypts and
decodes the fixed-size header, and validates the entry count, file-table offset,
and declared decompressed table size before replacing the stored pair. It does
not yet decompress the file table or validate individual archive entries. The
keyboard buffer is not yet consumed by the game engine; the current Win32/
Direct3D 8 entry point and SDL2/desktop-OpenGL runtime still need an iOS
platform implementation.

## Bring-up app

The XcodeGen project in `BringUp/project.yml` builds a SwiftUI app. It imports:

- `th08.dat`
- `thbgm.dat`

Both files must be selected together. They are staged under
`Application Support/TH08Data` and replace the previous pair only after both
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
runner. Both builds and the host-side keyboard bridge test passed for commit
`b545ef2`. An unsigned build is not an installable, signed IPA.

## Remaining engine integration

1. Introduce an iOS application entry point and lifecycle-aware frame loop.
2. Replace the Win32 window/message-pump boundary without changing reconstructed
   game logic or its exactness evidence.
3. Port Direct3D 8 device/resource/state behavior to a supported iOS graphics
   API and validate it against existing renderer captures.
4. Connect the keyboard-state ABI to the game's input polling and clear held
   keys on app deactivation.
5. Port audio, timing, save/config paths, focus handling, and full archive
   loading, including file-table decompression and entry validation.
6. Run the original game with user-imported archives on a physical iPhone and
   verify gameplay, audio, suspend/resume, and frame pacing.

Do not add a nominal Apple CMake target that links stubs in place of platform
services. Keep the original Windows/Linux targets and reconstruction sources
unchanged while the iOS boundary is developed.
