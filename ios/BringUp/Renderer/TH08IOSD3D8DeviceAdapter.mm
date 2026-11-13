#import "TH08IOSD3D8DeviceAdapter.h"
#import "TH08IOSD3D8StateMapping.h"
#import "TH08IOSD3D8VertexLayout.h"
#import "TH08IOSD3D8VertexConversion.h"
#include <limits>
#include <new>
#include <vector>
#include <math.h>
#include <string.h>

#import <Foundation/Foundation.h>

namespace {

bool IsFiniteMatrix(const TH08IOSD3D8::Matrix4 &matrix)
{
    for (size_t row = 0; row < 4; ++row)
        for (size_t column = 0; column < 4; ++column)
            if (!isfinite(matrix.m[row][column]))
                return false;
    return true;
}

bool IsValidD3DViewport(const TH08IOSD3D8::Viewport &viewport)
{
    return isfinite(viewport.x) && isfinite(viewport.y) &&
           isfinite(viewport.width) && isfinite(viewport.height) &&
           isfinite(viewport.minZ) && isfinite(viewport.maxZ) &&
           viewport.width > 0.0f && viewport.height > 0.0f &&
           viewport.maxZ > viewport.minZ;
}

TH08IOSD3D8::Matrix4 IdentityD3DMatrix()
{
    TH08IOSD3D8::Matrix4 matrix = {};
    for (size_t index = 0; index < 4; ++index)
        matrix.m[index][index] = 1.0f;
    return matrix;
}

} // namespace

@interface TH08IOSD3D8DeviceAdapter () {
    __weak TH08IOSGLRenderer *_renderer;
    uint32_t _renderStates[256];
    uint32_t _textureStates[32];
    NSMutableSet<NSNumber *> *_ownedTextures;
    GLuint _boundTexture;
    TH08IOSD3D8::Matrix4 _worldTransform;
    TH08IOSD3D8::Matrix4 _viewTransform;
    TH08IOSD3D8::Matrix4 _projectionTransform;
    TH08IOSD3D8::Matrix4 _textureTransform;
    TH08IOSD3D8::Viewport _d3dViewport;
    BOOL _hasD3DViewport;
}
@end

@implementation TH08IOSD3D8DeviceAdapter
- (nullable instancetype)initWithRenderer:(TH08IOSGLRenderer *)renderer
{
    if (renderer == nil) return nil;
    self = [super init];
    if (self == nil) return nil;
    _renderer = renderer;
    _ownedTextures = [[NSMutableSet alloc] init];
    _worldTransform = IdentityD3DMatrix();
    _viewTransform = IdentityD3DMatrix();
    _projectionTransform = IdentityD3DMatrix();
    _textureTransform = IdentityD3DMatrix();
    _hasD3DViewport = NO;
    _renderStates[19] = 5u;
    _renderStates[20] = 6u;
    _renderStates[23] = 4u;
    _renderStates[25] = 5u;
    _renderStates[36] = 0u;
    float fogEnd = 1.0f;
    memcpy(&_renderStates[37], &fogEnd, sizeof(fogEnd));
    _renderStates[168] = 0x0Fu;
    _renderStates[171] = 1u;
    _textureStates[1] = 4u;
    _textureStates[2] = 2u;
    _textureStates[3] = 0u;
    _textureStates[4] = 2u;
    _textureStates[5] = 2u;
    _textureStates[6] = 0u;
    _textureStates[13] = 1u;
    _textureStates[14] = 1u;
    _textureStates[16] = 2u;
    _textureStates[17] = 2u;
    if (![self applyRenderStates] || ![self applyTextureStageStates]) return nil;
    return self;
}

- (GLuint)createTextureWithRGBA8Pixels:(const void *)pixels
                                  width:(GLsizei)width
                                 height:(GLsizei)height
                               rowBytes:(size_t)rowBytes
{
    TH08IOSGLRenderer *renderer = _renderer;
    if (renderer == nil || pixels == NULL || width <= 0 || height <= 0)
        return 0u;
    const GLuint texture = [renderer createTextureWithRGBA8Pixels:pixels
                                                            width:width
                                                           height:height
                                                         rowBytes:rowBytes];
    if (texture == 0u)
        return 0u;
    NSNumber *key = [NSNumber numberWithUnsignedInt:texture];
    if ([_ownedTextures containsObject:key]) {
        [renderer deleteTexture:texture];
        return 0u;
    }
    [_ownedTextures addObject:key];
    return texture;
}

- (BOOL)deleteTexture:(GLuint)texture
{
    if (texture == 0u)
        return NO;
    NSNumber *key = [NSNumber numberWithUnsignedInt:texture];
    if (![_ownedTextures containsObject:key])
        return NO;
    TH08IOSGLRenderer *renderer = _renderer;
    if (renderer == nil || ![renderer isOwningContextCurrent])
        return NO;
    [renderer deleteTexture:texture];
    [_ownedTextures removeObject:key];
    if (_boundTexture == texture) _boundTexture = 0u;
    return YES;
}

- (BOOL)setTexture:(GLuint)texture
{
    if (texture != 0u &&
        ![_ownedTextures containsObject:[NSNumber numberWithUnsignedInt:texture]])
        return NO;
    _boundTexture = texture;
    return YES;
}

- (BOOL)drawBoundVertices:(const TH08IOSRendererVertex *)vertices
                    count:(GLsizei)count
                primitive:(TH08IOSRendererPrimitive)primitive
{
    return [self drawVertices:vertices count:count primitive:primitive texture:_boundTexture];
}

- (BOOL)drawFVFVertices:(const void *)vertices
                   fvf:(uint32_t)fvf
                 stride:(size_t)stride
                  count:(size_t)count
                  world:(const TH08IOSD3D8::Matrix4 &)world
                   view:(const TH08IOSD3D8::Matrix4 &)view
             projection:(const TH08IOSD3D8::Matrix4 &)projection
      textureTransform:(const TH08IOSD3D8::Matrix4 &)textureTransform
               viewport:(const TH08IOSD3D8::Viewport &)viewport
              primitive:(TH08IOSRendererPrimitive)primitive
{
    TH08IOSGLRenderer *renderer = _renderer;
    if (renderer == nil || ![renderer isOwningContextCurrent] ||
        vertices == NULL || count == 0u ||
        count > static_cast<size_t>(std::numeric_limits<GLsizei>::max()))
        return NO;

    TH08IOSD3D8::VertexLayout layout = {};
    if (TH08IOSD3D8::BuildVertexLayout(fvf, &layout) != TH08IOSD3D8::LayoutError::None)
        return NO;

    std::vector<TH08IOSD3D8::ConvertedVertex> converted;
    const TH08IOSD3D8::BatchConversionError conversionError =
        TH08IOSD3D8::ConvertVertices(layout, vertices, stride, count,
                                     world, view, projection, textureTransform,
                                     viewport, &converted);
    if (conversionError != TH08IOSD3D8::BatchConversionError::None ||
        converted.size() != count)
        return NO;

    std::vector<TH08IOSRendererVertex> rendererVertices;
    try {
        rendererVertices.resize(count);
    } catch (const std::bad_alloc &) {
        return NO;
    }

    for (size_t index = 0; index < count; ++index) {
        const TH08IOSD3D8::ConvertedVertex &source = converted[index];
        TH08IOSRendererVertex destination = {};
        TH08IOSD3D8::HomogeneousPosition screen = {};
        screen.x = source.x;
        screen.y = source.y;
        screen.z = source.z;
        screen.w = source.w;
        float clip[4] = {};
        if (!TH08IOSD3D8::ViewportToClipPosition(screen, viewport, clip))
            return NO;

        destination.x = clip[0];
        destination.y = clip[1];
        destination.z = clip[2];
        destination.positionW = clip[3];
        destination.u = source.u;
        destination.v = source.v;
        destination.red = source.red;
        destination.green = source.green;
        destination.blue = source.blue;
        destination.alpha = source.alpha;
        destination.fogCoordinate = source.fogCoordinate;
        destination.specularRed = source.specularRed;
        destination.specularGreen = source.specularGreen;
        destination.specularBlue = source.specularBlue;
        destination.specularAlpha = source.specularAlpha;
        rendererVertices[index] = destination;
    }

    const GLfloat identity[16] = {
        1.0f, 0.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, 0.0f, 1.0f
    };
    if (![renderer setTransformMatrix:identity])
        return NO;
    return [self drawBoundVertices:rendererVertices.data()
                             count:static_cast<GLsizei>(count)
                         primitive:primitive];
}

- (BOOL)drawVertices:(const TH08IOSRendererVertex *)vertices
               count:(GLsizei)count
           primitive:(TH08IOSRendererPrimitive)primitive
             texture:(GLuint)texture
{
    TH08IOSGLRenderer *renderer = _renderer;
    if (renderer == nil || vertices == NULL || count <= 0 ||
        ![renderer isOwningContextCurrent])
        return NO;
    if (texture != 0u &&
        ![_ownedTextures containsObject:[NSNumber numberWithUnsignedInt:texture]])
        return NO;
    return [renderer drawVertices:vertices count:count primitive:primitive texture:texture];
}

- (BOOL)applyRenderStates
{
    TH08IOSGLRenderer *renderer = _renderer;
    if (renderer == nil) return NO;
    GLenum sourceBlend, destinationBlend, blendOperation, depthFunction, alphaFunction;
    if (!TH08IOSD3D8::MapBlendFactor(_renderStates[19], &sourceBlend) ||
        !TH08IOSD3D8::MapBlendFactor(_renderStates[20], &destinationBlend) ||
        !TH08IOSD3D8::MapBlendOperation(_renderStates[171], &blendOperation) ||
        !TH08IOSD3D8::MapCompareFunction(_renderStates[23], &depthFunction) ||
        !TH08IOSD3D8::MapCompareFunction(_renderStates[25], &alphaFunction)) return NO;
    const uint32_t writeMask = _renderStates[168];
    if ((writeMask & ~0x0Fu) != 0u) return NO;
    float fogStart = 0.0f, fogEnd = 1.0f;
    memcpy(&fogStart, &_renderStates[36], sizeof(fogStart));
    memcpy(&fogEnd, &_renderStates[37], sizeof(fogEnd));
    if (!isfinite(fogStart) || !isfinite(fogEnd) || fogEnd <= fogStart) return NO;
    if (_renderStates[28] != 0u && _renderStates[140] != 3u) return NO;
    const uint32_t fogColor = _renderStates[34];
    if (![renderer setBlendingEnabled:_renderStates[27] != 0u sourceFactor:sourceBlend destinationFactor:destinationBlend] ||
        ![renderer setBlendEquation:blendOperation] ||
        ![renderer setColorWriteMaskRed:(writeMask & 1u) != 0u green:(writeMask & 2u) != 0u
                                   blue:(writeMask & 4u) != 0u alpha:(writeMask & 8u) != 0u]) return NO;
    [renderer setDepthTestingEnabled:_renderStates[7] != 0u writeEnabled:_renderStates[14] != 0u];
    if (![renderer setDepthCompareFunction:depthFunction] ||
        ![renderer setAlphaTestEnabled:_renderStates[15] != 0u compareFunction:alphaFunction
                              reference:(_renderStates[24] & 0xFFu) / 255.0f]) return NO;
    if (![renderer setFogEnabled:_renderStates[28] != 0u
                          colorRed:((fogColor >> 16) & 0xFFu) / 255.0f
                                 green:((fogColor >> 8) & 0xFFu) / 255.0f
                                  blue:(fogColor & 0xFFu) / 255.0f
                                  start:fogStart
                                    end:fogEnd]) return NO;
    const uint32_t factor = _renderStates[60];
    [renderer setTextureFactorRed:(factor >> 16) & 0xFFu green:(factor >> 8) & 0xFFu
                              blue:factor & 0xFFu alpha:(factor >> 24) & 0xFFu];
    return YES;
}

- (BOOL)applyTextureStageStates
{
    TH08IOSGLRenderer *renderer = _renderer;
    if (renderer == nil) return NO;
    TH08IOSD3D8::TextureOperation colorOperation, alphaOperation;
    TH08IOSD3D8::TextureArgumentState color1 = {}, color2 = {}, alpha1 = {}, alpha2 = {};
    GLenum minification, magnification, wrapS, wrapT;
    if (!TH08IOSD3D8::MapTextureOperation(_textureStates[1], &colorOperation) ||
        !TH08IOSD3D8::MapTextureArgumentState(_textureStates[2], &color1) ||
        !TH08IOSD3D8::MapTextureArgumentState(_textureStates[3], &color2) ||
        !TH08IOSD3D8::MapTextureOperation(_textureStates[4], &alphaOperation) ||
        !TH08IOSD3D8::MapTextureArgumentState(_textureStates[5], &alpha1) ||
        !TH08IOSD3D8::MapTextureArgumentState(_textureStates[6], &alpha2) ||
        !TH08IOSD3D8::MapTextureFilter(_textureStates[17], &minification) ||
        !TH08IOSD3D8::MapTextureFilter(_textureStates[16], &magnification) ||
        !TH08IOSD3D8::MapTextureAddress(_textureStates[13], &wrapS) ||
        !TH08IOSD3D8::MapTextureAddress(_textureStates[14], &wrapT)) return NO;
    if (![renderer setTextureStageColorOperation:(TH08IOSRendererTextureOperation)colorOperation
                                  colorArgument1:(TH08IOSRendererTextureArgument)color1.argument
                                  colorArgument2:(TH08IOSRendererTextureArgument)color2.argument
                                    alphaOperation:(TH08IOSRendererTextureOperation)alphaOperation
                                  alphaArgument1:(TH08IOSRendererTextureArgument)alpha1.argument
                                  alphaArgument2:(TH08IOSRendererTextureArgument)alpha2.argument] ||
        ![renderer setTextureStageArgumentModifiersColor1:color1.modifiers color2:color2.modifiers
                                                    alpha1:alpha1.modifiers alpha2:alpha2.modifiers] ||
        ![renderer setTextureMinificationFilter:minification magnificationFilter:magnification wrapS:wrapS wrapT:wrapT])
        return NO;
    return YES;
}

- (BOOL)setWorldTransform:(const TH08IOSD3D8::Matrix4 &)transform
{
    if (!IsFiniteMatrix(transform)) return NO;
    _worldTransform = transform;
    return YES;
}

- (BOOL)setViewTransform:(const TH08IOSD3D8::Matrix4 &)transform
{
    if (!IsFiniteMatrix(transform)) return NO;
    _viewTransform = transform;
    return YES;
}

- (BOOL)setProjectionTransform:(const TH08IOSD3D8::Matrix4 &)transform
{
    if (!IsFiniteMatrix(transform)) return NO;
    _projectionTransform = transform;
    return YES;
}

- (BOOL)setTextureTransform:(const TH08IOSD3D8::Matrix4 &)transform
{
    if (!IsFiniteMatrix(transform)) return NO;
    _textureTransform = transform;
    return YES;
}

- (BOOL)setD3DViewport:(const TH08IOSD3D8::Viewport &)viewport
{
    TH08IOSGLRenderer *renderer = _renderer;
    if (renderer == nil || ![renderer isOwningContextCurrent] ||
        !IsValidD3DViewport(viewport) || viewport.x < 0.0f || viewport.y < 0.0f ||
        viewport.x > static_cast<float>(std::numeric_limits<GLint>::max()) ||
        viewport.y > static_cast<float>(std::numeric_limits<GLint>::max()) ||
        viewport.width > static_cast<float>(std::numeric_limits<GLsizei>::max()) ||
        viewport.height > static_cast<float>(std::numeric_limits<GLsizei>::max()) ||
        floorf(viewport.x) != viewport.x || floorf(viewport.y) != viewport.y ||
        floorf(viewport.width) != viewport.width ||
        floorf(viewport.height) != viewport.height)
        return NO;
    if (![renderer setViewportX:static_cast<GLint>(viewport.x)
                              y:static_cast<GLint>(viewport.y)
                          width:static_cast<GLsizei>(viewport.width)
                         height:static_cast<GLsizei>(viewport.height)])
        return NO;
    _d3dViewport = viewport;
    _hasD3DViewport = YES;
    return YES;
}

- (BOOL)drawCurrentFVFVertices:(const void *)vertices
                           fvf:(uint32_t)fvf
                         stride:(size_t)stride
                          count:(size_t)count
                      primitive:(TH08IOSRendererPrimitive)primitive
{
    if (!_hasD3DViewport) return NO;
    return [self drawFVFVertices:vertices
                             fvf:fvf
                           stride:stride
                            count:count
                            world:_worldTransform
                             view:_viewTransform
                       projection:_projectionTransform
                textureTransform:_textureTransform
                         viewport:_d3dViewport
                        primitive:primitive];
}

- (BOOL)setRenderState:(uint32_t)state value:(uint32_t)value
{
    TH08IOSD3D8::RenderState mapped;
    if (state >= 256u || !TH08IOSD3D8::MapRenderState(state, &mapped)) return NO;
    switch (mapped) {
    case TH08IOSD3D8::RenderState::ZEnable:
    case TH08IOSD3D8::RenderState::ZWriteEnable:
    case TH08IOSD3D8::RenderState::AlphaTestEnable:
    case TH08IOSD3D8::RenderState::AlphaBlendEnable:
    case TH08IOSD3D8::RenderState::FogEnable:
        if (value > 1u) return NO;
        break;
    case TH08IOSD3D8::RenderState::AlphaReference:
        if (value > 255u) return NO;
        break;
    default: break;
    }
    const uint32_t previous = _renderStates[state];
    _renderStates[state] = value;
    if ([self applyRenderStates]) return YES;
    _renderStates[state] = previous;
    [self applyRenderStates];
    return NO;
}

- (BOOL)setTextureStageState:(uint32_t)stage state:(uint32_t)state value:(uint32_t)value
{
    TH08IOSD3D8::TextureStageState mapped;
    if (stage != 0u || state >= 32u || !TH08IOSD3D8::MapTextureStageState(state, &mapped)) return NO;
    const uint32_t previous = _textureStates[state];
    _textureStates[state] = value;
    if ([self applyTextureStageStates]) return YES;
    _textureStates[state] = previous;
    [self applyTextureStageStates];
    return NO;
}
@end
