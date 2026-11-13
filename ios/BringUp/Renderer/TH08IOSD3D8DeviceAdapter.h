#import <Foundation/Foundation.h>
#import "TH08IOSGLRenderer.h"
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
- (BOOL)drawVertices:(const TH08IOSRendererVertex *)vertices
               count:(GLsizei)count
           primitive:(TH08IOSRendererPrimitive)primitive
             texture:(GLuint)texture;
- (BOOL)setRenderState:(uint32_t)state value:(uint32_t)value;
- (BOOL)setTextureStageState:(uint32_t)stage state:(uint32_t)state value:(uint32_t)value;
@end
NS_ASSUME_NONNULL_END
