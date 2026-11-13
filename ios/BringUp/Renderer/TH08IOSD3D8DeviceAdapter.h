#import <Foundation/Foundation.h>
#import "TH08IOSGLRenderer.h"
#import "TH08IOSD3D8Transform.h"
#include <stdint.h>
NS_ASSUME_NONNULL_BEGIN
@interface TH08IOSD3D8DeviceAdapter : NSObject
- (nullable instancetype)initWithRenderer:(TH08IOSGLRenderer *)renderer;
- (GLuint)createTextureWithRGBA8Pixels:(const void *)pixels
                                  width:(GLsizei)width
                                 height:(GLsizei)height
                               rowBytes:(size_t)rowBytes;
- (BOOL)deleteTexture:(GLuint)texture;
// Mirrors the single active D3D8 texture stage. Zero unbinds the texture.
- (BOOL)setTexture:(GLuint)texture;
- (BOOL)drawBoundVertices:(const TH08IOSRendererVertex *)vertices
                    count:(GLsizei)count
                primitive:(TH08IOSRendererPrimitive)primitive;
// Converts an interleaved D3D8 FVF batch through the supplied fixed-function
// transforms and viewport, then submits it to the ES2 renderer. The renderer
// transform is set to identity because positions are already in clip space.
- (BOOL)drawFVFVertices:(const void *)vertices
                   fvf:(uint32_t)fvf
                 stride:(size_t)stride
                  count:(size_t)count
                  world:(const TH08IOSD3D8::Matrix4 &)world
                   view:(const TH08IOSD3D8::Matrix4 &)view
             projection:(const TH08IOSD3D8::Matrix4 &)projection
      textureTransform:(const TH08IOSD3D8::Matrix4 &)textureTransform
               viewport:(const TH08IOSD3D8::Viewport &)viewport
              primitive:(TH08IOSRendererPrimitive)primitive;
- (BOOL)drawVertices:(const TH08IOSRendererVertex *)vertices
               count:(GLsizei)count
           primitive:(TH08IOSRendererPrimitive)primitive
             texture:(GLuint)texture;
- (BOOL)setWorldTransform:(const TH08IOSD3D8::Matrix4 &)transform;
- (BOOL)setViewTransform:(const TH08IOSD3D8::Matrix4 &)transform;
- (BOOL)setProjectionTransform:(const TH08IOSD3D8::Matrix4 &)transform;
- (BOOL)setTextureTransform:(const TH08IOSD3D8::Matrix4 &)transform;
- (BOOL)setD3DViewport:(const TH08IOSD3D8::Viewport &)viewport;
- (BOOL)clearColorEnabled:(BOOL)clearColor color:(uint32_t)color
            depthEnabled:(BOOL)clearDepth depth:(float)depth;
- (BOOL)drawCurrentFVFVertices:(const void *)vertices
                           fvf:(uint32_t)fvf
                         stride:(size_t)stride
                          count:(size_t)count
                      primitive:(TH08IOSRendererPrimitive)primitive;
- (BOOL)setRenderState:(uint32_t)state value:(uint32_t)value;
- (BOOL)setTextureStageState:(uint32_t)stage state:(uint32_t)state value:(uint32_t)value;
@end
NS_ASSUME_NONNULL_END
