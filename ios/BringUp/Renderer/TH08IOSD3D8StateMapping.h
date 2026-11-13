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

static inline bool MapTextureArgument(uint32_t d3dArgument, TextureArgument *output)
{
    if (output == NULL || (d3dArgument & ~0x0Fu) != 0u)
        return false; // Complement/alpha-replicate modifiers need shader support.
    switch (d3dArgument & 0x0Fu) {
    case 0u: *output = TextureArgumentDiffuse; return true; // D3DTA_DIFFUSE
    case 2u: *output = TextureArgumentTexture; return true; // D3DTA_TEXTURE
    case 3u: *output = TextureArgumentFactor; return true; // D3DTA_TFACTOR
    default: return false; // CURRENT/SPECULAR/TEMP are not silently approximated.
    }
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
