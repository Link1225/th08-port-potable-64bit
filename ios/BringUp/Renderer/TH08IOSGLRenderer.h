#import <Foundation/Foundation.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct TH08IOSRendererVertex {
    GLfloat x;
    GLfloat y;
    GLfloat z;
    GLfloat u;
    GLfloat v;
    GLubyte red;
    GLubyte green;
    GLubyte blue;
    GLubyte alpha;
    GLfloat fogCoordinate;
} TH08IOSRendererVertex;

typedef NS_ENUM(GLint, TH08IOSRendererTextureOperation) {
    TH08IOSRendererTextureOperationSelectArg1 = 0,
    TH08IOSRendererTextureOperationSelectArg2 = 1,
    TH08IOSRendererTextureOperationModulate = 2,
    TH08IOSRendererTextureOperationAdd = 3,
    TH08IOSRendererTextureOperationSubtract = 4,
    TH08IOSRendererTextureOperationAddSigned = 5,
    TH08IOSRendererTextureOperationModulate2X = 6,
    TH08IOSRendererTextureOperationModulate4X = 7
};

typedef NS_ENUM(GLint, TH08IOSRendererTextureArgument) {
    TH08IOSRendererTextureArgumentTexture = 0,
    TH08IOSRendererTextureArgumentDiffuse = 1,
    TH08IOSRendererTextureArgumentFactor = 2
};

typedef NS_ENUM(NSUInteger, TH08IOSRendererPrimitive) {
    TH08IOSRendererPrimitivePoints = GL_POINTS,
    TH08IOSRendererPrimitiveLines = GL_LINES,
    TH08IOSRendererPrimitiveLineStrip = GL_LINE_STRIP,
    TH08IOSRendererPrimitiveTriangles = GL_TRIANGLES,
    TH08IOSRendererPrimitiveTriangleStrip = GL_TRIANGLE_STRIP,
    TH08IOSRendererPrimitiveTriangleFan = GL_TRIANGLE_FAN
};

// A deliberately small ES2 renderer core. The object retains the EAGLContext
// current at initialization. Make that same context current before every API
// call; calls made with a different context are rejected. Deallocation switches
// to the owning context temporarily to release GL resources, then restores the
// previously current context.
@interface TH08IOSGLRenderer : NSObject

- (nullable instancetype)initWithCurrentContext;
- (BOOL)setViewportX:(GLint)x y:(GLint)y width:(GLsizei)width height:(GLsizei)height;
- (BOOL)setBlendingEnabled:(BOOL)enabled
             sourceFactor:(GLenum)sourceFactor
        destinationFactor:(GLenum)destinationFactor;
- (BOOL)setBlendEquation:(GLenum)equation;
- (BOOL)setColorWriteMaskRed:(BOOL)red green:(BOOL)green blue:(BOOL)blue alpha:(BOOL)alpha;
- (BOOL)setTextureStageColorOperation:(TH08IOSRendererTextureOperation)colorOperation
                      colorArgument1:(TH08IOSRendererTextureArgument)colorArgument1
                      colorArgument2:(TH08IOSRendererTextureArgument)colorArgument2
                        alphaOperation:(TH08IOSRendererTextureOperation)alphaOperation
                      alphaArgument1:(TH08IOSRendererTextureArgument)alphaArgument1
                      alphaArgument2:(TH08IOSRendererTextureArgument)alphaArgument2;
- (void)setTextureFactorRed:(GLubyte)red green:(GLubyte)green blue:(GLubyte)blue alpha:(GLubyte)alpha;
- (BOOL)setFogEnabled:(BOOL)enabled colorRed:(GLfloat)red green:(GLfloat)green blue:(GLfloat)blue start:(GLfloat)start end:(GLfloat)end;
// ES2 non-mipmap sampling modes. Defaults are linear filtering and clamp-to-edge.
- (BOOL)setTextureMinificationFilter:(GLenum)minificationFilter
                    magnificationFilter:(GLenum)magnificationFilter
                                  wrapS:(GLenum)wrapS
                                  wrapT:(GLenum)wrapT;
// Matrix is a standard column-major OpenGL 4x4 transform; defaults to identity.
- (BOOL)setTransformMatrix:(const GLfloat *)columnMajorMatrix;
// Alpha comparison uses OpenGL ES comparison enums (GL_NEVER ... GL_ALWAYS).
- (BOOL)setAlphaTestEnabled:(BOOL)enabled
            compareFunction:(GLenum)compareFunction
                  reference:(GLfloat)reference;
- (BOOL)setDepthCompareFunction:(GLenum)compareFunction;
// Scissor coordinates use OpenGL's bottom-left origin.
- (BOOL)setScissorEnabled:(BOOL)enabled
                        x:(GLint)x
                        y:(GLint)y
                    width:(GLsizei)width
                   height:(GLsizei)height;
- (void)setDepthTestingEnabled:(BOOL)enabled writeEnabled:(BOOL)writeEnabled;
- (void)clearRed:(GLfloat)red green:(GLfloat)green blue:(GLfloat)blue alpha:(GLfloat)alpha
           depth:(GLfloat)depth;
- (GLuint)createTextureWithRGBA8Pixels:(const void *)pixels
                                 width:(GLsizei)width
                                height:(GLsizei)height
                              rowBytes:(size_t)rowBytes;
// Render targets are RGBA8 textures with a 16-bit depth attachment.
// Pass texture 0 to bind the original framebuffer captured at initialization.
- (GLuint)createRenderTargetWithWidth:(GLsizei)width height:(GLsizei)height;
- (BOOL)bindRenderTargetTexture:(GLuint)texture;
// Reads the currently bound framebuffer in RGBA8, bottom row first (OpenGL order).
- (nullable NSData *)copyCurrentFramebufferRGBA8PixelsWithWidth:(GLsizei)width
                                                         height:(GLsizei)height;
- (void)deleteTexture:(GLuint)texture;
- (BOOL)drawVertices:(const TH08IOSRendererVertex *)vertices
               count:(GLsizei)count
           primitive:(TH08IOSRendererPrimitive)primitive
             texture:(GLuint)texture;

@end

NS_ASSUME_NONNULL_END
