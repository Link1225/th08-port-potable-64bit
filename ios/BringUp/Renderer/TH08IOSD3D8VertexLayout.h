#pragma once

#include <stddef.h>
#include <stdint.h>
#include <string.h>

// D3D8 FVF bits used by the TH08 Linux compatibility renderer. This header is
// platform-neutral so the iOS adapter can validate and decode engine vertices
// without importing Win32 or desktop OpenGL headers.
namespace TH08IOSD3D8 {

static const uint32_t FVF_XYZ = 0x002u;
static const uint32_t FVF_XYZRHW = 0x004u;
static const uint32_t FVF_POSITION_MASK = 0x400Eu;
static const uint32_t FVF_NORMAL = 0x010u;
static const uint32_t FVF_PSIZE = 0x020u;
static const uint32_t FVF_DIFFUSE = 0x040u;
static const uint32_t FVF_SPECULAR = 0x080u;
static const uint32_t FVF_TEXCOUNT_MASK = 0x0F00u;
static const uint32_t FVF_TEXCOUNT_SHIFT = 8u;
static const uint32_t FVF_TEXCOORDSIZE_MASK = 0xFFFF0000u;

static inline uint32_t FVF_TEXCOORDSIZE1(uint32_t index)
{
    return 3u << (16u + index * 2u);
}
static inline uint32_t FVF_TEXCOORDSIZE3(uint32_t index)
{
    return 1u << (16u + index * 2u);
}
static inline uint32_t FVF_TEXCOORDSIZE4(uint32_t index)
{
    return 2u << (16u + index * 2u);
}

enum class LayoutError {
    None,
    NullOutput,
    UnsupportedPosition,
    UnsupportedFlags,
    TooManyTextureCoordinates,
    InvalidTextureCoordinateSize,
    NullVertex,
    StrideTooSmall
};

struct VertexLayout {
    uint32_t fvf;
    size_t positionOffset;
    size_t normalOffset;
    size_t pointSizeOffset;
    size_t diffuseOffset;
    size_t specularOffset;
    size_t textureCoordinateOffset;
    size_t requiredStride;
    uint8_t positionComponents;
    uint8_t textureCoordinateCount;
    uint8_t textureCoordinate0Components;
    bool transformed;
};

struct DecodedVertex {
    float x;
    float y;
    float z;
    float rhw;
    float u;
    float v;
    uint8_t red;
    uint8_t green;
    uint8_t blue;
    uint8_t alpha;
    float fogCoordinate;
    uint8_t specularRed;
    uint8_t specularGreen;
    uint8_t specularBlue;
    uint8_t specularAlpha;
};

static inline uint8_t TextureCoordinateComponents(uint32_t fvf, uint32_t index)
{
    const uint32_t encoded = (fvf >> (16u + index * 2u)) & 3u;
    switch (encoded) {
    case 0u: return 2u;
    case 1u: return 3u;
    case 2u: return 4u;
    case 3u: return 1u;
    default: return 0u;
    }
}

static inline LayoutError BuildVertexLayout(uint32_t fvf, VertexLayout *output)
{
    if (output == NULL)
        return LayoutError::NullOutput;

    const uint32_t position = fvf & FVF_POSITION_MASK;
    const bool transformed = position == FVF_XYZRHW;
    if (position != FVF_XYZ && !transformed)
        return LayoutError::UnsupportedPosition;

    const uint32_t textureCount = (fvf & FVF_TEXCOUNT_MASK) >> FVF_TEXCOUNT_SHIFT;
    if (textureCount > 8u)
        return LayoutError::TooManyTextureCoordinates;

    const uint32_t knownBits = FVF_POSITION_MASK | FVF_NORMAL | FVF_PSIZE |
        FVF_DIFFUSE | FVF_SPECULAR | FVF_TEXCOUNT_MASK | FVF_TEXCOORDSIZE_MASK;
    if ((fvf & ~knownBits) != 0u)
        return LayoutError::UnsupportedFlags;

    VertexLayout layout = {};
    layout.fvf = fvf;
    layout.positionOffset = 0;
    layout.positionComponents = transformed ? 4u : 3u;
    layout.transformed = transformed;
    size_t offset = transformed ? 16u : 12u;

    layout.normalOffset = SIZE_MAX;
    if ((fvf & FVF_NORMAL) != 0u) {
        layout.normalOffset = offset;
        offset += 12u;
    }
    layout.pointSizeOffset = SIZE_MAX;
    if ((fvf & FVF_PSIZE) != 0u) {
        layout.pointSizeOffset = offset;
        offset += 4u;
    }
    layout.diffuseOffset = SIZE_MAX;
    if ((fvf & FVF_DIFFUSE) != 0u) {
        layout.diffuseOffset = offset;
        offset += 4u;
    }
    layout.specularOffset = SIZE_MAX;
    if ((fvf & FVF_SPECULAR) != 0u) {
        layout.specularOffset = offset;
        offset += 4u;
    }

    layout.textureCoordinateOffset = SIZE_MAX;
    layout.textureCoordinateCount = static_cast<uint8_t>(textureCount);
    layout.textureCoordinate0Components = 0u;
    if (textureCount != 0u) {
        layout.textureCoordinateOffset = offset;
        for (uint32_t index = 0; index < textureCount; ++index) {
            const uint8_t components = TextureCoordinateComponents(fvf, index);
            if (components < 1u || components > 4u)
                return LayoutError::InvalidTextureCoordinateSize;
            if (index == 0u)
                layout.textureCoordinate0Components = components;
            offset += static_cast<size_t>(components) * sizeof(float);
        }
    }
    layout.requiredStride = offset;
    *output = layout;
    return LayoutError::None;
}

static inline float ReadFloat(const uint8_t *bytes)
{
    float value;
    memcpy(&value, bytes, sizeof(value));
    return value;
}

static inline LayoutError DecodeVertex(const VertexLayout &layout,
                                       const void *vertexBytes,
                                       size_t stride,
                                       DecodedVertex *output)
{
    if (vertexBytes == NULL || output == NULL)
        return LayoutError::NullVertex;
    if (stride < layout.requiredStride)
        return LayoutError::StrideTooSmall;

    const uint8_t *bytes = static_cast<const uint8_t *>(vertexBytes);
    DecodedVertex decoded = {};
    decoded.x = ReadFloat(bytes + layout.positionOffset);
    decoded.y = ReadFloat(bytes + layout.positionOffset + sizeof(float));
    decoded.z = ReadFloat(bytes + layout.positionOffset + 2u * sizeof(float));
    decoded.rhw = layout.transformed ? ReadFloat(bytes + layout.positionOffset + 3u * sizeof(float)) : 1.0f;
    decoded.red = decoded.green = decoded.blue = decoded.alpha = 255u;
    decoded.specularRed = decoded.specularGreen = decoded.specularBlue = decoded.specularAlpha = 0u;
    if (layout.diffuseOffset != SIZE_MAX) {
        uint32_t color;
        memcpy(&color, bytes + layout.diffuseOffset, sizeof(color));
        // D3DCOLOR is 0xAARRGGBB in the little-endian TH08 target.
        decoded.blue = static_cast<uint8_t>(color & 0xFFu);
        decoded.green = static_cast<uint8_t>((color >> 8u) & 0xFFu);
        decoded.red = static_cast<uint8_t>((color >> 16u) & 0xFFu);
        decoded.alpha = static_cast<uint8_t>((color >> 24u) & 0xFFu);
    }
    if (layout.specularOffset != SIZE_MAX) {
        uint32_t color;
        memcpy(&color, bytes + layout.specularOffset, sizeof(color));
        decoded.specularBlue = static_cast<uint8_t>(color & 0xFFu);
        decoded.specularGreen = static_cast<uint8_t>((color >> 8u) & 0xFFu);
        decoded.specularRed = static_cast<uint8_t>((color >> 16u) & 0xFFu);
        decoded.specularAlpha = static_cast<uint8_t>((color >> 24u) & 0xFFu);
    }
    if (layout.textureCoordinateCount != 0u) {
        const uint8_t *uv = bytes + layout.textureCoordinateOffset;
        decoded.u = ReadFloat(uv);
        decoded.v = layout.textureCoordinate0Components >= 2u
            ? ReadFloat(uv + sizeof(float)) : 0.0f;
    }
    // D3D8 fog is derived from the view-space transform, not stored in FVF.
    // The device adapter must fill this after applying world/view matrices.
    decoded.fogCoordinate = 0.0f;
    *output = decoded;
    return LayoutError::None;
}

} // namespace TH08IOSD3D8
