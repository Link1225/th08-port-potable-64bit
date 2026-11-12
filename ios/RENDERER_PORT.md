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

## Current next blocker

A renderer implementation cannot be considered complete from a successful SwiftUI build. The existing iOS app remains a data-import and keyboard bring-up shell. The original engine still has no iOS frame loop, renderer, audio integration, or game target. The next code milestone is the explicit shader-backed renderer and its render-state/vertex tests; the existing desktop renderer should remain untouched until the new path can be compared.
