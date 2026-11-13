#pragma once

#include "TH08IOSD3D8VertexLayout.h"
#include "TH08IOSD3D8Transform.h"

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
    *output = result;
    return LayoutError::None;
}

} // namespace TH08IOSD3D8
