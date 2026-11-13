#pragma once

#import <OpenGLES/ES2/gl.h>

#include <stdint.h>

// Explicitly maps the D3D8 values exercised by TH08's single texture stage to
// the small ES2 renderer API. Unsupported operations/arguments fail closed;
// callers must not silently substitute a visually different operation.
namespace TH08IOSD3D8 {

enum TextureOperation {
    TextureSelectArg1 = 0,
    TextureSelectArg2 = 1,
    TextureModulate = 2,
    TextureAdd = 3,
    TextureSubtract = 4,
    TextureAddSigned = 5,
    TextureModulate2X = 6,
    TextureModulate4X = 7
};

enum TextureArgument {
    TextureArgumentTexture = 0,
    TextureArgumentDiffuse = 1,
    TextureArgumentFactor = 2
};


enum class RenderState {
    ZEnable,
    ZWriteEnable,
    AlphaTestEnable,
    SourceBlend,
    DestinationBlend,
    ZFunction,
    AlphaReference,
    AlphaFunction,
    AlphaBlendEnable,
    FogEnable,
    FogColor,
    FogStart,
    FogEnd,
    TextureFactor,
    ColorWriteEnable,
    BlendOperation,
    FogVertexMode
};

enum class TextureStageState {
    ColorOperation,
    ColorArgument1,
    ColorArgument2,
    AlphaOperation,
    AlphaArgument1,
    AlphaArgument2,
    AddressU,
    AddressV,
    MagnificationFilter,
    MinificationFilter
};

// D3D8 enum values are intentionally kept here instead of importing d3d8.h;
// this header remains usable by the iOS target and its host-independent tests.
static inline bool MapRenderState(uint32_t d3dState, RenderState *output)
{
    if (output == NULL)
        return false;
    switch (d3dState) {
    case 7u: *output = RenderState::ZEnable; return true;
    case 14u: *output = RenderState::ZWriteEnable; return true;
    case 15u: *output = RenderState::AlphaTestEnable; return true;
    case 19u: *output = RenderState::SourceBlend; return true;
    case 20u: *output = RenderState::DestinationBlend; return true;
    case 23u: *output = RenderState::ZFunction; return true;
    case 24u: *output = RenderState::AlphaReference; return true;
    case 25u: *output = RenderState::AlphaFunction; return true;
    case 27u: *output = RenderState::AlphaBlendEnable; return true;
    case 28u: *output = RenderState::FogEnable; return true;
    case 34u: *output = RenderState::FogColor; return true;
    case 36u: *output = RenderState::FogStart; return true;
    case 37u: *output = RenderState::FogEnd; return true;
    case 60u: *output = RenderState::TextureFactor; return true;
    case 140u: *output = RenderState::FogVertexMode; return true;
    case 168u: *output = RenderState::ColorWriteEnable; return true;
    case 171u: *output = RenderState::BlendOperation; return true;
    default: return false;
    }
}

static inline bool MapTextureStageState(uint32_t d3dState, TextureStageState *output)
{
    if (output == NULL)
        return false;
    switch (d3dState) {
    case 1u: *output = TextureStageState::ColorOperation; return true;
    case 2u: *output = TextureStageState::ColorArgument1; return true;
    case 3u: *output = TextureStageState::ColorArgument2; return true;
    case 4u: *output = TextureStageState::AlphaOperation; return true;
    case 5u: *output = TextureStageState::AlphaArgument1; return true;
    case 6u: *output = TextureStageState::AlphaArgument2; return true;
    case 13u: *output = TextureStageState::AddressU; return true;
    case 14u: *output = TextureStageState::AddressV; return true;
    case 16u: *output = TextureStageState::MagnificationFilter; return true;
    case 17u: *output = TextureStageState::MinificationFilter; return true;
    default: return false;
    }
}

enum TextureArgumentModifier {
    TextureArgumentModifierNone = 0,
    TextureArgumentModifierComplement = 1u << 0,
    TextureArgumentModifierAlphaReplicate = 1u << 1
};

struct TextureArgumentState {
    TextureArgument argument;
    uint8_t modifiers;
};

static inline bool MapTextureOperation(uint32_t d3dOperation, TextureOperation *output)
{
    if (output == NULL)
        return false;
    switch (d3dOperation) {
    case 2u: *output = TextureSelectArg1; return true; // D3DTOP_SELECTARG1
    case 3u: *output = TextureSelectArg2; return true; // D3DTOP_SELECTARG2
    case 4u: *output = TextureModulate; return true; // D3DTOP_MODULATE
    case 7u: *output = TextureAdd; return true; // D3DTOP_ADD
    case 10u: *output = TextureSubtract; return true; // D3DTOP_SUBTRACT
    case 8u: *output = TextureAddSigned; return true; // D3DTOP_ADDSIGNED
    case 5u: *output = TextureModulate2X; return true; // D3DTOP_MODULATE2X
    case 6u: *output = TextureModulate4X; return true; // D3DTOP_MODULATE4X
    default: return false;
    }
}

// D3DTA argument selectors occupy the low nibble. The two modifiers are
// independent bits and may be combined; reserved high bits fail closed.
static inline bool MapTextureArgumentState(uint32_t d3dArgument,
                                           TextureArgumentState *output)
{
    if (output == NULL || (d3dArgument & ~0x3Fu) != 0u)
        return false;

    TextureArgumentState result = {};
    switch (d3dArgument & 0x0Fu) {
    case 0u: result.argument = TextureArgumentDiffuse; break; // D3DTA_DIFFUSE
    case 2u: result.argument = TextureArgumentTexture; break; // D3DTA_TEXTURE
    case 3u: result.argument = TextureArgumentFactor; break; // D3DTA_TFACTOR
    default: return false; // CURRENT/SPECULAR/TEMP require separate stage semantics.
    }

    if ((d3dArgument & 0x10u) != 0u)
        result.modifiers |= TextureArgumentModifierComplement;
    if ((d3dArgument & 0x20u) != 0u)
        result.modifiers |= TextureArgumentModifierAlphaReplicate;
    *output = result;
    return true;
}

// Convenience mapping for call sites that cannot yet consume modifiers.
static inline bool MapTextureArgument(uint32_t d3dArgument, TextureArgument *output)
{
    if (output == NULL)
        return false;
    TextureArgumentState state = {};
    if (!MapTextureArgumentState(d3dArgument, &state) ||
        state.modifiers != TextureArgumentModifierNone)
        return false;
    *output = state.argument;
    return true;
}

static inline bool MapCompareFunction(uint32_t d3dFunction, GLenum *output)
{
    if (output == NULL)
        return false;
    switch (d3dFunction) {
    case 1u: *output = GL_NEVER; return true;
    case 2u: *output = GL_LESS; return true;
    case 3u: *output = GL_EQUAL; return true;
    case 4u: *output = GL_LEQUAL; return true;
    case 5u: *output = GL_GREATER; return true;
    case 6u: *output = GL_NOTEQUAL; return true;
    case 7u: *output = GL_GEQUAL; return true;
    case 8u: *output = GL_ALWAYS; return true;
    default: return false;
    }
}

static inline bool MapBlendFactor(uint32_t d3dFactor, GLenum *output)
{
    if (output == NULL)
        return false;
    switch (d3dFactor) {
    case 1u: *output = GL_ZERO; return true;
    case 2u: *output = GL_ONE; return true;
    case 3u: *output = GL_SRC_COLOR; return true;
    case 4u: *output = GL_ONE_MINUS_SRC_COLOR; return true;
    case 5u: *output = GL_SRC_ALPHA; return true;
    case 6u: *output = GL_ONE_MINUS_SRC_ALPHA; return true;
    case 7u: *output = GL_DST_ALPHA; return true;
    case 8u: *output = GL_ONE_MINUS_DST_ALPHA; return true;
    case 9u: *output = GL_DST_COLOR; return true;
    case 10u: *output = GL_ONE_MINUS_DST_COLOR; return true;
    case 11u: *output = GL_SRC_ALPHA_SATURATE; return true;
    default: return false;
    }
}

static inline bool MapBlendOperation(uint32_t d3dOperation, GLenum *output)
{
    if (output == NULL)
        return false;
    switch (d3dOperation) {
    case 1u: *output = GL_FUNC_ADD; return true; // D3DBLENDOP_ADD
    case 2u: *output = GL_FUNC_SUBTRACT; return true; // D3DBLENDOP_SUBTRACT
    case 3u: *output = GL_FUNC_REVERSE_SUBTRACT; return true; // D3DBLENDOP_REVSUBTRACT
    default: return false; // MIN/MAX require ES2 extension support.
    }
}

static inline bool MapTextureFilter(uint32_t d3dFilter, GLenum *output)
{
    if (output == NULL)
        return false;
    switch (d3dFilter) {
    case 1u: *output = GL_NEAREST; return true; // D3DTEXF_POINT
    case 2u: *output = GL_LINEAR; return true; // D3DTEXF_LINEAR
    default: return false; // Mipmapped filters need a complete mip chain.
    }
}

static inline bool MapTextureAddress(uint32_t d3dAddress, GLenum *output)
{
    if (output == NULL)
        return false;
    switch (d3dAddress) {
    case 1u: *output = GL_REPEAT; return true; // D3DTADDRESS_WRAP
    case 2u: *output = GL_MIRRORED_REPEAT; return true; // D3DTADDRESS_MIRROR
    case 3u: *output = GL_CLAMP_TO_EDGE; return true; // D3DTADDRESS_CLAMP
    default: return false; // Border and mirror-once are not equivalent in ES2.
    }
}

} // namespace TH08IOSD3D8
