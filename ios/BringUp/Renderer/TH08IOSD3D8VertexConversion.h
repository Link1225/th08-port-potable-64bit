#pragma once

#include "TH08IOSD3D8VertexLayout.h"
#include "TH08IOSD3D8Transform.h"
#include <limits>
#include <vector>

namespace TH08IOSD3D8 {

struct ConvertedVertex {
    float x;
    float y;
    float z;
    float w;
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

static inline LayoutError ConvertVertex(const VertexLayout &layout,
                                        const void *vertexBytes,
                                        size_t stride,
                                        const Matrix4 &world,
                                        const Matrix4 &view,
                                        const Matrix4 &projection,
                                        const Matrix4 &textureTransform,
                                        const Viewport &viewport,
                                        ConvertedVertex *output)
{
    if (output == NULL)
        return LayoutError::NullOutput;

    DecodedVertex decoded = {};
    const LayoutError decodeError = DecodeVertex(layout, vertexBytes, stride, &decoded);
    if (decodeError != LayoutError::None)
        return decodeError;

    HomogeneousPosition position = {};
    bool transformed = false;
    if (layout.transformed) {
        const float xyzw[4] = {decoded.x, decoded.y, decoded.z, decoded.rhw};
        transformed = TransformXYZRHW(xyzw, &position);
    } else {
        const float xyz[3] = {decoded.x, decoded.y, decoded.z};
        transformed = TransformXYZ(xyz, world, view, projection, viewport, &position);
    }
    if (!transformed)
        return LayoutError::UnsupportedPosition;

    ConvertedVertex result = {};
    result.x = position.x;
    result.y = position.y;
    result.z = position.z;
    result.w = position.w;
    TransformTextureCoordinate(decoded.u, decoded.v, textureTransform,
                               &result.u, &result.v);
    result.red = decoded.red;
    result.green = decoded.green;
    result.blue = decoded.blue;
    result.alpha = decoded.alpha;
    result.fogCoordinate = position.fogCoordinate;
    result.specularRed = decoded.specularRed;
    result.specularGreen = decoded.specularGreen;
    result.specularBlue = decoded.specularBlue;
    result.specularAlpha = decoded.specularAlpha;
    *output = result;
    return LayoutError::None;
}


enum class BatchConversionError {
    None,
    NullInput,
    NullOutput,
    CountOverflow,
    VertexDecodeFailed
};

// Converts a complete interleaved D3D8 vertex batch transactionally. The
// caller receives no partial output when any vertex has an invalid layout or
// stride. Input may have padding between vertices; output is tightly packed.
static inline BatchConversionError ConvertVertices(
    const VertexLayout &layout,
    const void *vertexBytes,
    size_t stride,
    size_t count,
    const Matrix4 &world,
    const Matrix4 &view,
    const Matrix4 &projection,
    const Matrix4 &textureTransform,
    const Viewport &viewport,
    std::vector<ConvertedVertex> *output)
{
    if (output == NULL)
        return BatchConversionError::NullOutput;
    if (count != 0u && vertexBytes == NULL)
        return BatchConversionError::NullInput;
    if (count > std::numeric_limits<size_t>::max() / sizeof(ConvertedVertex))
        return BatchConversionError::CountOverflow;
    if (count != 0u && stride < layout.requiredStride)
        return BatchConversionError::VertexDecodeFailed;
    if (count > 1u && stride != 0u &&
        count - 1u > std::numeric_limits<size_t>::max() / stride)
        return BatchConversionError::CountOverflow;

    std::vector<ConvertedVertex> converted;
    converted.reserve(count);
    const uint8_t *source = static_cast<const uint8_t *>(vertexBytes);
    for (size_t index = 0; index < count; ++index) {
        ConvertedVertex vertex = {};
        const LayoutError error = ConvertVertex(
            layout, source + index * stride, stride,
            world, view, projection, textureTransform, viewport, &vertex);
        if (error != LayoutError::None)
            return BatchConversionError::VertexDecodeFailed;
        converted.push_back(vertex);
    }
    output->swap(converted);
    return BatchConversionError::None;
}

} // namespace TH08IOSD3D8
