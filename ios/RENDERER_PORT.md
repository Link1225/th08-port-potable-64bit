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
  leaving an offscreen target.

This foundation is intentionally not represented as a Direct3D 8 replacement.
It has not yet been compared against the Linux renderer's deterministic output,
and no game-engine call site uses it. CI compile success establishes only that
these Objective-C++/ES2 APIs compile for the selected SDKs; it does not establish
rendering parity or device performance.

## Current next blocker

The existing iOS app remains a data-import and keyboard bring-up shell. The
original engine still has no iOS frame loop, full renderer adapter, audio
integration, or game target. The next renderer milestone is a deterministic
ES2 offscreen render test suite (texture upload/readback, transforms, alpha,
blend/depth and render-target switching) that can be compared against the Linux
adapter's reference captures. After that, implement the missing D3D8 semantics
and connect the renderer to the engine. Keep the existing desktop renderer
untouched until the new path can be compared.
