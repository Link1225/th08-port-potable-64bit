# iOS renderer port investigation

## Current renderer boundary

The only implemented modern renderer is `src/modern/linux/d3d8_compat.cpp`. It is not an iOS renderer: it includes desktop OpenGL headers, creates an SDL desktop GL context, and uses desktop-only fixed-function state. The iOS bring-up app does not compile this file or link the game engine.

The file's GL entry points were inventoried from the current `port/portable-64bit` source:

- Immediate-mode drawing: three `glBegin/glEnd` blocks. Two draw a four-vertex triangle strip for texture/backbuffer presentation; the third emits the game's D3D primitive stream, including transformed positions, diffuse color, texture coordinates and optional fog coordinate.
- Fixed-function matrices: `glMatrixMode`, `glPushMatrix`, `glPopMatrix`, `glLoadIdentity`, and `glOrtho`.
- Fixed-function texture environment and alpha/fog state: `glTexEnvi`, `glAlphaFunc`, `glFogi`, `glFogfv`, `glFogf`, and `glTexEnvfv`.
- Desktop-only or unavailable-in-ES functionality: `glPushAttrib/glPopAttrib`, `glFogCoordf`, `glClipControl`, and `glDrawBuffer`. The framebuffer/renderbuffer entry points are dynamically loaded through SDL.
- The adapter also owns texture upload/readback, pixel-format conversion, viewport/scissor, depth/blend state, framebuffer setup, and SDL window/context presentation.

OpenGL ES 2 does not provide the compatibility fixed-function pipeline used here. Replacing the include or requesting an ES context would therefore not make this renderer work. iOS also does not provide the desktop GL context and extension behavior assumed by this adapter.

## Required implementation sequence

1. Keep the Linux adapter unchanged as the existing desktop reference.
2. Extract the D3D8-facing behavior from the Linux-specific GL calls into a platform-neutral renderer contract only where the existing D3D8 methods and state semantics are understood.
3. Implement an iOS renderer against a supported iOS graphics API. For an ES2 path, use explicit shaders, vertex attributes and matrix uniforms; emulate the small immediate-mode surface by collecting vertices and issuing `glDrawArrays`. Implement explicit state save/restore in place of attribute stacks, and replace fog-coordinate input with a shader attribute.
4. Preserve D3D8 texture formats, blend/depth/alpha comparisons, viewport/scissor orientation, render-target readback and presentation semantics. Validate each against the Linux adapter's deterministic render captures before integrating it with the engine.
5. Only then add the renderer and SDL/iOS host to a real engine target. Do not add an Apple target that links stubs or a bring-up-only screen and label it a game port.

## Implemented ES2 foundation

The bring-up target now contains `TH08IOSGLRenderer`, which owns the
`EAGLContext` used to create its GL resources and rejects resource/draw calls
made with a different current context. It provides:

- explicit position/UV/RGBA shaders and streamed vertex-buffer draws for the
  ES2 primitive-array set;
- column-major transform uniforms and fragment-shader alpha comparisons for
  all eight comparison functions;
- validated ES2 blend factors, depth-test/write state and viewport management;
- configurable non-mipmap min/mag filtering and S/T wrap modes;
- RGBA8 texture uploads with row-stride packing, overflow checks, allocation
  failure cleanup, and restoration of the previous texture binding and unpack
  alignment;
- offscreen RGBA8 render-target textures with 16-bit depth renderbuffers,
  framebuffer completeness checks, explicit bind/unbind, and owned-resource
  cleanup. The original framebuffer and its latest viewport are restored when
  leaving an offscreen target;
- RGBA8 readback of the currently bound framebuffer with overflow checks and
  restoration of the previous pack alignment. Returned rows use OpenGL's
  bottom-to-top order;
- a GLKit-backed view in the bring-up app that creates the ES2 renderer and
  submits a small smoke-test triangle to the view's drawable framebuffer.
- a platform-neutral D3D8 FVF layout decoder that validates XYZ/XYZRHW
  layouts, accounts for optional normal/point-size/diffuse/specular fields and
  up to eight texture-coordinate sets, and decodes the first set and D3DCOLOR
  without unaligned loads;
- a fail-closed mapping table for the D3DTOP subset, texture arguments without
  complement/alpha-replicate modifiers, all eight D3D comparison functions,
  and the eleven standard D3D blend factors supported by ES2.
- D3D row-vector world/view/projection transform helpers, including viewport
  mapping, view-space fog-coordinate capture, pre-transformed XYZRHW reciprocal-W
  handling, and the Linux adapter's texture-matrix coordinate convention.

The XCTest suite now exercises offscreen readback and switching, texture
sampling, transforms, alpha comparisons, blend/depth state, viewport restore,
scissor and clear behavior, color-write masks, blend equations, texture-factor
combining, linear fog, and cleanup of all four enabled vertex attributes after
a draw. It also checks FVF offsets/decoding, transformed vertex layout,
additional texture-coordinate set skipping, unsupported FVF rejection, and
the supported D3D state mappings, world/view/projection and viewport
math, XYZRHW reciprocal-W handling, and texture-matrix coordinates. These are
unit tests, not a parity test against the Linux adapter's deterministic output.

This foundation is intentionally not represented as a Direct3D 8 replacement.
No game-engine call site uses it. CI compile/test success establishes that the
bring-up target and covered renderer operations work in the simulator
environment; it does not establish rendering parity or physical-device
performance.

## Current next blocker

The iOS app remains a data-import and keyboard bring-up shell with a renderer
smoke preview. The original engine still has no iOS frame loop, full renderer
adapter, audio integration, or game target. The immediate renderer task is to
build a D3D8-facing device adapter over the ES2 renderer. It must translate the
existing device calls and state arrays, decode the engine's FVF vertex layouts
(including pre-transformed XYZRHW vertices), reproduce the Linux adapter's
position/viewport and texture-transform conventions, and cover the original
texture operations, argument modifiers, fog and render-target semantics.
Create deterministic comparison captures from the Linux adapter before
connecting this adapter to the engine. Keep the existing desktop renderer
untouched until the new path can be compared.
