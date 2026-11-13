#import "TH08IOSGLRenderer.h"

#include <stddef.h>
#include <stdint.h>

namespace {

static const char *kVertexShader =
    "attribute vec3 a_position;\n"
    "attribute vec2 a_texcoord;\n"
    "attribute vec4 a_color;\n"
    "varying vec2 v_texcoord;\n"
    "varying vec4 v_color;\n"
    "void main() {\n"
    "  gl_Position = vec4(a_position, 1.0);\n"
    "  v_texcoord = a_texcoord;\n"
    "  v_color = a_color;\n"
    "}\n";

static const char *kFragmentShader =
    "precision mediump float;\n"
    "uniform sampler2D u_texture;\n"
    "uniform float u_textured;\n"
    "varying vec2 v_texcoord;\n"
    "varying vec4 v_color;\n"
    "void main() {\n"
    "  vec4 texel = mix(vec4(1.0), texture2D(u_texture, v_texcoord), u_textured);\n"
    "  gl_FragColor = texel * v_color;\n"
    "}\n";

GLuint CompileShader(GLenum type, const char *source)
{
    GLuint shader = glCreateShader(type);
    if (shader == 0)
        return 0;
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);
    GLint compiled = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if (compiled != GL_TRUE) {
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

GLuint CreateProgram()
{
    GLuint vertex = CompileShader(GL_VERTEX_SHADER, kVertexShader);
    if (vertex == 0)
        return 0;
    GLuint fragment = CompileShader(GL_FRAGMENT_SHADER, kFragmentShader);
    if (fragment == 0) {
        glDeleteShader(vertex);
        return 0;
    }

    GLuint program = glCreateProgram();
    if (program != 0) {
        glAttachShader(program, vertex);
        glAttachShader(program, fragment);
        glBindAttribLocation(program, 0, "a_position");
        glBindAttribLocation(program, 1, "a_texcoord");
        glBindAttribLocation(program, 2, "a_color");
        glLinkProgram(program);
        GLint linked = GL_FALSE;
        glGetProgramiv(program, GL_LINK_STATUS, &linked);
        if (linked != GL_TRUE) {
            glDeleteProgram(program);
            program = 0;
        }
    }
    glDeleteShader(vertex);
    glDeleteShader(fragment);
    return program;
}

bool IsValidTextureSize(GLsizei width, GLsizei height, size_t rowBytes)
{
    if (width <= 0 || height <= 0)
        return false;
    const size_t minimumRow = static_cast<size_t>(width) * 4u;
    if (rowBytes < minimumRow)
        return false;
    return static_cast<size_t>(height - 1) <= (SIZE_MAX - minimumRow) / rowBytes;
}

} // namespace

@interface TH08IOSGLRenderer () {
    GLuint _program;
    GLint _samplerLocation;
    GLint _texturedLocation;
    BOOL _blendingEnabled;
    BOOL _depthTestingEnabled;
    BOOL _depthWriteEnabled;
    GLenum _sourceFactor;
    GLenum _destinationFactor;
    BOOL _hasViewport;
}
@end

@implementation TH08IOSGLRenderer

- (nullable instancetype)initWithCurrentContext
{
    self = [super init];
    if (self == nil)
        return nil;
    if ([EAGLContext currentContext] == nil) {
        return nil;
    }

    _program = CreateProgram();
    if (_program == 0)
        return nil;

    _samplerLocation = glGetUniformLocation(_program, "u_texture");
    _texturedLocation = glGetUniformLocation(_program, "u_textured");
    _blendingEnabled = NO;
    _depthTestingEnabled = NO;
    _depthWriteEnabled = YES;
    _sourceFactor = GL_SRC_ALPHA;
    _destinationFactor = GL_ONE_MINUS_SRC_ALPHA;
    _hasViewport = NO;
    return self;
}

- (void)dealloc
{
    if (_program != 0 && [EAGLContext currentContext] != nil)
        glDeleteProgram(_program);
}

- (BOOL)setViewportX:(GLint)x y:(GLint)y width:(GLsizei)width height:(GLsizei)height
{
    if ([EAGLContext currentContext] == nil || width <= 0 || height <= 0)
        return NO;
    glViewport(x, y, width, height);
    _hasViewport = YES;
    return YES;
}

- (void)setBlendingEnabled:(BOOL)enabled
             sourceFactor:(GLenum)sourceFactor
        destinationFactor:(GLenum)destinationFactor
{
    _blendingEnabled = enabled;
    _sourceFactor = sourceFactor;
    _destinationFactor = destinationFactor;
}

- (void)setDepthTestingEnabled:(BOOL)enabled writeEnabled:(BOOL)writeEnabled
{
    _depthTestingEnabled = enabled;
    _depthWriteEnabled = writeEnabled;
}

- (void)applyDrawState
{
    if (_blendingEnabled) {
        glEnable(GL_BLEND);
        glBlendFunc(_sourceFactor, _destinationFactor);
    } else {
        glDisable(GL_BLEND);
    }
    if (_depthTestingEnabled)
        glEnable(GL_DEPTH_TEST);
    else
        glDisable(GL_DEPTH_TEST);
    glDepthMask(_depthWriteEnabled ? GL_TRUE : GL_FALSE);
}

- (void)clearRed:(GLfloat)red green:(GLfloat)green blue:(GLfloat)blue alpha:(GLfloat)alpha
           depth:(GLfloat)depth
{
    if ([EAGLContext currentContext] == nil)
        return;
    glClearColor(red, green, blue, alpha);
    glClearDepthf(depth);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}

- (GLuint)createTextureWithRGBA8Pixels:(const void *)pixels
                                 width:(GLsizei)width
                                height:(GLsizei)height
                              rowBytes:(size_t)rowBytes
{
    if ([EAGLContext currentContext] == nil || pixels == NULL ||
        !IsValidTextureSize(width, height, rowBytes))
        return 0;

    GLuint texture = 0;
    glGenTextures(1, &texture);
    if (texture == 0)
        return 0;

    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    const size_t packedRow = static_cast<size_t>(width) * 4u;
    const uint8_t *source = static_cast<const uint8_t *>(pixels);
    if (rowBytes == packedRow) {
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0,
                     GL_RGBA, GL_UNSIGNED_BYTE, source);
    } else {
        NSMutableData *packed = [NSMutableData dataWithLength:packedRow * static_cast<size_t>(height)];
        uint8_t *destination = static_cast<uint8_t *>(packed.mutableBytes);
        for (GLsizei row = 0; row < height; ++row)
            memcpy(destination + static_cast<size_t>(row) * packedRow,
                   source + static_cast<size_t>(row) * rowBytes, packedRow);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0,
                     GL_RGBA, GL_UNSIGNED_BYTE, destination);
    }
    return texture;
}

- (void)deleteTexture:(GLuint)texture
{
    if (texture != 0 && [EAGLContext currentContext] != nil)
        glDeleteTextures(1, &texture);
}

- (BOOL)drawVertices:(const TH08IOSRendererVertex *)vertices
               count:(GLsizei)count
           primitive:(TH08IOSRendererPrimitive)primitive
             texture:(GLuint)texture
{
    if ([EAGLContext currentContext] == nil || !_hasViewport ||
        vertices == NULL || count <= 0 || _program == 0)
        return NO;

    glUseProgram(_program);
    [self applyDrawState];
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texture);
    glUniform1i(_samplerLocation, 0);
    glUniform1f(_texturedLocation, texture != 0 ? 1.0f : 0.0f);

    const GLsizei stride = static_cast<GLsizei>(sizeof(TH08IOSRendererVertex));
    glEnableVertexAttribArray(0);
    glEnableVertexAttribArray(1);
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride,
                          reinterpret_cast<const GLvoid *>(offsetof(TH08IOSRendererVertex, x)));
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, stride,
                          reinterpret_cast<const GLvoid *>(offsetof(TH08IOSRendererVertex, u)));
    glVertexAttribPointer(2, 4, GL_UNSIGNED_BYTE, GL_TRUE, stride,
                          reinterpret_cast<const GLvoid *>(offsetof(TH08IOSRendererVertex, red)));
    glDrawArrays(static_cast<GLenum>(primitive), 0, count);
    glDisableVertexAttribArray(0);
    glDisableVertexAttribArray(1);
    glDisableVertexAttribArray(2);
    return glGetError() == GL_NO_ERROR;
}

@end
