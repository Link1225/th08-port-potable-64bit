#import "TH08IOSD3D8DeviceAdapter.h"
#import "TH08IOSD3D8StateMapping.h"
#include <math.h>
#include <string.h>

#import <Foundation/Foundation.h>

@interface TH08IOSD3D8DeviceAdapter () {
    __weak TH08IOSGLRenderer *_renderer;
    uint32_t _renderStates[256];
    uint32_t _textureStates[32];
    NSMutableSet<NSNumber *> *_ownedTextures;
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
    return YES;
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
