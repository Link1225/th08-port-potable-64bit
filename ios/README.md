# iOS port

This directory contains the native iOS host application and the platform
adapters needed to bring the original TH08 engine onto iPhone and iPad.

The current checkpoint is deliberately limited to a safe, user-owned game-data
import shell. It does not yet launch the game: the existing runtime entry point
in `src/main.cpp` is a Win32/Direct3D 8 application, and the current portable
renderer is an SDL2/desktop-OpenGL adapter. Neither is an iOS host.

## Bring-up app

The XcodeGen project in `BringUp/project.yml` builds a small SwiftUI app. It
imports the two archives supplied by the user:

- `th08.dat`
- `thbgm.dat`

Both files must be selected together. The app stages them under
`Application Support/TH08Data` and replaces the previous pair only after both
copies have succeeded. Game archives are never committed to this repository.

## Build

On a macOS machine with Xcode and XcodeGen installed:

```sh
cd ios/BringUp
xcodegen generate
xcodebuild -project TH08BringUp.xcodeproj \
  -scheme TH08BringUp -sdk iphonesimulator \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

The GitHub Actions workflow `.github/workflows/ios-bringup.yml` performs this
unsigned Simulator build on a macOS runner.

## Remaining engine integration

1. Introduce an iOS application entry point and lifecycle-aware frame loop.
2. Replace the Win32 window/message-pump boundary without changing reconstructed
   game logic or its exactness evidence.
3. Port the Direct3D 8 device/resource/state behavior to a supported iOS graphics
   API and validate it against the existing renderer captures.
4. Route physical Bluetooth keyboard events into the game's DirectInput-compatible
   input state. No touch controls are planned.
5. Port audio, timing, save/config paths, focus handling, and archive loading.
6. Run the original game with user-imported archives on a physical iPhone and
   verify gameplay, audio, suspend/resume, and frame pacing.

Do not add a nominal Apple CMake target that links stubs in place of these
platform services. Keep the original Windows/Linux targets and reconstruction
sources unchanged while the iOS boundary is developed.
