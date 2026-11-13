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
} TH08IOSRendererVertex;

typedef NS_ENUM(NSUInteger, TH08IOSRendererPrimitive) {
    TH08IOSRendererPrimitivePoints = GL_POINTS,
    TH08IOSRendererPrimitiveLines = GL_LINES,
    TH08IOSRendererPrimitiveLineStrip = GL_LINE_STRIP,
    TH08IOSRendererPrimitiveTriangles = GL_TRIANGLES,
    TH08IOSRendererPrimitiveTriangleStrip = GL_TRIANGLE_STRIP,
    TH08IOSRendererPrimitiveTriangleFan = GL_TRIANGLE_FAN
};

// A deliberately small ES2 renderer core. The caller must make the owning
// EAGLContext current before creating or using this object.
@interface TH08IOSGLRenderer : NSObject

- (nullable instancetype)initWithCurrentContext;
- (BOOL)setViewportX:(GLint)x y:(GLint)y width:(GLsizei)width height:(GLsizei)height;
- (void)setBlendingEnabled:(BOOL)enabled
             sourceFactor:(GLenum)sourceFactor
        destinationFactor:(GLenum)destinationFactor;
// Matrix is a standard column-major OpenGL 4x4 transform; defaults to identity.
- (BOOL)setTransformMatrix:(const GLfloat *)columnMajorMatrix;
// Alpha comparison uses OpenGL ES comparison enums (GL_NEVER ... GL_ALWAYS).
- (BOOL)setAlphaTestEnabled:(BOOL)enabled
            compareFunction:(GLenum)compareFunction
                  reference:(GLfloat)reference;
- (void)setDepthTestingEnabled:(BOOL)enabled writeEnabled:(BOOL)writeEnabled;
- (void)clearRed:(GLfloat)red green:(GLfloat)green blue:(GLfloat)blue alpha:(GLfloat)alpha
           depth:(GLfloat)depth;
- (GLuint)createTextureWithRGBA8Pixels:(const void *)pixels
                                 width:(GLsizei)width
                                height:(GLsizei)height
                              rowBytes:(size_t)rowBytes;
- (void)deleteTexture:(GLuint)texture;
- (BOOL)drawVertices:(const TH08IOSRendererVertex *)vertices
               count:(GLsizei)count
           primitive:(TH08IOSRendererPrimitive)primitive
             texture:(GLuint)texture;

@end

NS_ASSUME_NONNULL_END
