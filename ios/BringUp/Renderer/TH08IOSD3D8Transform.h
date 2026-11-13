#pragma once

#include <math.h>
#include <stddef.h>

namespace TH08IOSD3D8 {

// D3DMATRIX-compatible row-major storage. Vectors multiply on the left,
// matching the existing Linux adapter's TransformPosition implementation.
struct Matrix4 {
    float m[4][4];
};

struct Viewport {
    float x;
    float y;
    float width;
    float height;
    float minZ;
    float maxZ;
};

struct HomogeneousPosition {
    float x;
    float y;
    float z;
    float w;
    float fogCoordinate;
};

static inline void MultiplyRowVector(const float input[4], const Matrix4 &matrix,
                                     float output[4])
{
    for (size_t column = 0; column < 4; ++column) {
        output[column] = input[0] * matrix.m[0][column] +
                         input[1] * matrix.m[1][column] +
                         input[2] * matrix.m[2][column] +
                         input[3] * matrix.m[3][column];
    }
}

static inline bool TransformXYZ(const float position[3],
                                const Matrix4 &world,
                                const Matrix4 &view,
                                const Matrix4 &projection,
                                const Viewport &viewport,
                                HomogeneousPosition *output)
{
    if (position == NULL || output == NULL ||
        !(viewport.width > 0.0f) || !(viewport.height > 0.0f))
        return false;

    float vector[4] = {position[0], position[1], position[2], 1.0f};
    float next[4];
    MultiplyRowVector(vector, world, next);
    MultiplyRowVector(next, view, vector);
    const float fogCoordinate = fabsf(vector[2]);
    MultiplyRowVector(vector, projection, next);

    const float w = next[3];
    HomogeneousPosition result;
    result.x = (viewport.x + 0.5f) * w + (next[0] + w) * viewport.width * 0.5f;
    result.y = (viewport.y + 0.5f) * w + (w - next[1]) * viewport.height * 0.5f;
    result.z = viewport.minZ * w + next[2] * (viewport.maxZ - viewport.minZ);
    result.w = w;
    result.fogCoordinate = fogCoordinate;
    *output = result;
    return true;
}


static inline bool ViewportToClipPosition(const HomogeneousPosition &screenPosition,
                                          const Viewport &viewport,
                                          float output[4])
{
    if (output == NULL || !(viewport.width > 0.0f) ||
        !(viewport.height > 0.0f) || !(viewport.maxZ > viewport.minZ) ||
        !isfinite(screenPosition.x) || !isfinite(screenPosition.y) ||
        !isfinite(screenPosition.z) || !isfinite(screenPosition.w) ||
        !isfinite(viewport.x) || !isfinite(viewport.y) ||
        !isfinite(viewport.width) || !isfinite(viewport.height) ||
        !isfinite(viewport.minZ) || !isfinite(viewport.maxZ))
        return false;

    const float w = screenPosition.w;
    const float ndcX = 2.0f * (screenPosition.x - (viewport.x + 0.5f) * w) /
                       viewport.width - w;
    const float ndcY = w - 2.0f * (screenPosition.y - (viewport.y + 0.5f) * w) /
                       viewport.height;
    const float depth = (screenPosition.z - viewport.minZ * w) /
                        (viewport.maxZ - viewport.minZ);
    const float result[4] = {ndcX, ndcY, (2.0f * depth - 1.0f) * w, w};
    for (size_t index = 0; index < 4; ++index)
        if (!isfinite(result[index]))
            return false;
    for (size_t index = 0; index < 4; ++index)
        output[index] = result[index];
    return true;
}

static inline bool TransformXYZRHW(const float position[4],
                                   HomogeneousPosition *output)
{
    if (position == NULL || output == NULL)
        return false;
    const float inverseW = position[3] != 0.0f ? 1.0f / position[3] : 1.0f;
    HomogeneousPosition result;
    result.x = (position[0] + 0.5f) * inverseW;
    result.y = (position[1] + 0.5f) * inverseW;
    result.z = position[2] * inverseW;
    result.w = inverseW;
    result.fogCoordinate = 0.0f;
    *output = result;
    return true;
}

static inline void TransformTextureCoordinate(float u, float v,
                                              const Matrix4 &textureTransform,
                                              float *outU, float *outV)
{
    if (outU != NULL)
        *outU = u * textureTransform.m[0][0] +
                v * textureTransform.m[1][0] + textureTransform.m[2][0];
    if (outV != NULL)
        *outV = u * textureTransform.m[0][1] +
                v * textureTransform.m[1][1] + textureTransform.m[2][1];
}

} // namespace TH08IOSD3D8
