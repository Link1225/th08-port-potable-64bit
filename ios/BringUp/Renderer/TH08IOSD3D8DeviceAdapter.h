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
- (BOOL)setRenderState:(uint32_t)state value:(uint32_t)value;
- (BOOL)setTextureStageState:(uint32_t)stage state:(uint32_t)state value:(uint32_t)value;
@end
NS_ASSUME_NONNULL_END
