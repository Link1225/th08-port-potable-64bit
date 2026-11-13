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
textures, applies explicit blend/depth/viewport state, accepts a column-major
4×4 transform matrix, and implements fragment-shader alpha comparison for
Direct3D 8 alpha-test modes. The renderer retains its creating `EAGLContext`,
rejects draw/resource calls made under a different context, and temporarily
restores its owning context during teardown to release GL objects safely. It is compiled into
the bring-up target so both Simulator and device SDK builds validate the iOS
graphics API integration.

The current state subset includes:

- Blend enable, validated source/destination factors, and blend equations
  (add, subtract, and reverse-subtract).
- Independent RGBA color-write masks. Clear operations temporarily override
  color/depth write masks and scissor state, then restore the caller's state.
- Depth testing, depth write enable, and configurable depth comparison.
- Scissor rectangles, viewport control, and RGBA8 framebuffer readback.
- Texture sampling with non-mipmap nearest/linear filters and clamp, repeat,
  or mirrored-repeat wrapping.
- A shader-based texture-stage subset: select argument 1/2, modulate, add,
  subtract, add-signed, modulate-2x, and modulate-4x, with texture, diffuse
  vertex color, or constant texture-factor arguments for color and alpha.
- Per-vertex linear fog coordinates with configurable fog color and start/end.
- A column-major 4×4 matrix uniform and fragment-shader alpha comparisons.

The current bring-up also contains
`TH08IOSD3D8DeviceAdapter`, a partial Direct3D 8 compatibility layer. It
stores world/view/projection/texture transforms and viewport state, validates
the supported render and texture-stage states, owns RGBA8 textures, converts
interleaved FVF vertex batches (including XYZ and XYZRHW positions), maps D3D
viewport coordinates back to ES2 clip space, and submits the converted
vertices to the renderer. Tests cover the conversion path, transformed
vertices, viewport state, texture ownership, and invalid input handling.

This remains a renderer foundation, not a Direct3D 8 replacement. The adapter
is not an implementation of the complete `IDirect3DDevice8` interface. It
does not yet cover every D3D8 render/texture-stage state, all FVF layouts,
texture formats, mipmaps, multiple texture stages, the full surface/vertex
buffer/resource lifecycle, or the original engine's exact fog generation.
The game engine does not call this renderer or adapter yet. The original
Win32/Direct3D 8 entry point and SDL2/desktop-OpenGL runtime still need an iOS
platform implementation.

An initial `TH08EngineCore` static-library target is now declared in the XcodeGen
project. It is intended to compile the reconstructed game translation units for
the iOS SDK (excluding the Win32 `main.cpp` entry point and all Linux runtime
sources). It reuses the portable Win32/DirectX type declarations under
`src/modern/linux/include` and defines an iOS-specific compatibility preinclude.
This is a compile-only integration checkpoint: it does not provide the required
Win32 runtime functions, a Direct3D 8 COM device, an audio backend, or a frame-loop
entry point, and the app does not link or execute the library yet. CI must compile
this target successfully before it can be treated as a working engine build.

## Bring-up app

The XcodeGen project in `BringUp/project.yml` builds a SwiftUI app. Its bring-up screen instantiates the ES2 renderer inside a GLKit-backed OpenGL ES view and draws a small colored triangle into the view's drawable framebuffer. This confirms that the renderer is used by the app's view lifecycle, but it is only a renderer smoke preview, not game output. The app also imports:

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

## Target device

The intended physical device is **iPhone 14 Plus**. The app target is a
universal iOS application with an iOS 15.0 deployment target, and the generic
iOS device build checks the arm64 device SDK path. The current GitHub Actions
runner does not provide an iPhone 14 Plus simulator device type, so renderer
tests use the available iPhone 16 Plus simulator as a similar large-screen
proxy. This simulator proxy does not replace testing on the actual iPhone 14
Plus.

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
