#import "TH08IOSGLRenderer.h"

#include <stddef.h>
#include <stdint.h>
#include <math.h>
#include <string.h>

namespace {

static const char *kVertexShader =
    "attribute vec3 a_position;\n"
    "uniform mat4 u_transform;\n"
    "attribute vec2 a_texcoord;\n"
    "attribute vec4 a_color;\n"
    "varying vec2 v_texcoord;\n"
    "varying vec4 v_color;\n"
    "void main() {\n"
    "  gl_Position = u_transform * vec4(a_position, 1.0);\n"
    "  v_texcoord = a_texcoord;\n"
    "  v_color = a_color;\n"
    "}\n";

static const char *kFragmentShader =
    "precision mediump float;\n"
    "uniform sampler2D u_texture;\n"
    "uniform float u_textured;\n"
    "uniform float u_alpha_test_enabled;\n"
    "uniform int u_alpha_test_function;\n"
    "uniform float u_alpha_test_reference;\n"
    "varying vec2 v_texcoord;\n"
    "varying vec4 v_color;\n"
    "void main() {\n"
    "  vec4 texel = mix(vec4(1.0), texture2D(u_texture, v_texcoord), u_textured);\n"
    "  vec4 result = texel * v_color;\n"
    "  if (u_alpha_test_enabled > 0.5) {\n"
    "    float a = result.a;\n"
    "    bool pass = true;\n"
    "    if (u_alpha_test_function == 0) pass = false;\n"
    "    else if (u_alpha_test_function == 1) pass = a < u_alpha_test_reference;\n"
    "    else if (u_alpha_test_function == 2) pass = a == u_alpha_test_reference;\n"
    "    else if (u_alpha_test_function == 3) pass = a <= u_alpha_test_reference;\n"
    "    else if (u_alpha_test_function == 4) pass = a > u_alpha_test_reference;\n"
    "    else if (u_alpha_test_function == 5) pass = a != u_alpha_test_reference;\n"
    "    else if (u_alpha_test_function == 6) pass = a >= u_alpha_test_reference;\n"
    "    if (!pass) discard;\n"
    "  }\n"
    "  gl_FragColor = result;\n"
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
    GLuint _vertexBuffer;
    GLint _samplerLocation;
    GLint _texturedLocation;
    GLint _transformLocation;
    GLint _alphaTestEnabledLocation;
    GLint _alphaTestFunctionLocation;
    GLint _alphaTestReferenceLocation;
    GLfloat _transform[16];
    BOOL _alphaTestEnabled;
    GLint _alphaTestFunction;
    GLfloat _alphaTestReference;
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
    if ([EAGLContext currentContext] == nil)
        return nil;

    _program = CreateProgram();
    if (_program == 0)
        return nil;
    glGenBuffers(1, &_vertexBuffer);
    if (_vertexBuffer == 0) {
        glDeleteProgram(_program);
        _program = 0;
        return nil;
    }

    _samplerLocation = glGetUniformLocation(_program, "u_texture");
    _texturedLocation = glGetUniformLocation(_program, "u_textured");
    _transformLocation = glGetUniformLocation(_program, "u_transform");
    _alphaTestEnabledLocation = glGetUniformLocation(_program, "u_alpha_test_enabled");
    _alphaTestFunctionLocation = glGetUniformLocation(_program, "u_alpha_test_function");
    _alphaTestReferenceLocation = glGetUniformLocation(_program, "u_alpha_test_reference");
    for (NSUInteger index = 0; index < 16; ++index)
        _transform[index] = (index % 5) == 0 ? 1.0f : 0.0f;
    _alphaTestEnabled = NO;
    _alphaTestFunction = 7;
    _alphaTestReference = 0.0f;
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
    if ([EAGLContext currentContext] != nil) {
        if (_vertexBuffer != 0)
            glDeleteBuffers(1, &_vertexBuffer);
        if (_program != 0)
            glDeleteProgram(_program);
    }
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

- (BOOL)setTransformMatrix:(const GLfloat *)columnMajorMatrix
{
    if (columnMajorMatrix == NULL)
        return NO;
    for (NSUInteger index = 0; index < 16; ++index) {
        if (!isfinite(columnMajorMatrix[index]))
            return NO;
    }
    memcpy(_transform, columnMajorMatrix, sizeof(_transform));
    return YES;
}

- (BOOL)setAlphaTestEnabled:(BOOL)enabled
            compareFunction:(GLenum)compareFunction
                  reference:(GLfloat)reference
{
    GLint function = 7;
    switch (compareFunction) {
    case GL_NEVER: function = 0; break;
    case GL_LESS: function = 1; break;
    case GL_EQUAL: function = 2; break;
    case GL_LEQUAL: function = 3; break;
    case GL_GREATER: function = 4; break;
    case GL_NOTEQUAL: function = 5; break;
    case GL_GEQUAL: function = 6; break;
    case GL_ALWAYS: function = 7; break;
    default: return NO;
    }
    if (!isfinite(reference))
        return NO;
    _alphaTestEnabled = enabled;
    _alphaTestFunction = function;
    _alphaTestReference = reference < 0.0f ? 0.0f : (reference > 1.0f ? 1.0f : reference);
    return YES;
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
        vertices == NULL || count <= 0 || _program == 0 || _vertexBuffer == 0)
        return NO;

    const size_t vertexBytes = static_cast<size_t>(count) * sizeof(TH08IOSRendererVertex);
    if (vertexBytes / sizeof(TH08IOSRendererVertex) != static_cast<size_t>(count) ||
        vertexBytes > static_cast<size_t>(PTRDIFF_MAX))
        return NO;

    while (glGetError() != GL_NO_ERROR) {}
    glUseProgram(_program);
    glUniformMatrix4fv(_transformLocation, 1, GL_FALSE, _transform);
    glUniform1f(_alphaTestEnabledLocation, _alphaTestEnabled ? 1.0f : 0.0f);
    glUniform1i(_alphaTestFunctionLocation, _alphaTestFunction);
    glUniform1f(_alphaTestReferenceLocation, _alphaTestReference);
    [self applyDrawState];
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texture);
    glUniform1i(_samplerLocation, 0);
    glUniform1f(_texturedLocation, texture != 0 ? 1.0f : 0.0f);

    glBindBuffer(GL_ARRAY_BUFFER, _vertexBuffer);
    glBufferData(GL_ARRAY_BUFFER, static_cast<GLsizeiptr>(vertexBytes),
                 vertices, GL_STREAM_DRAW);
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
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    return glGetError() == GL_NO_ERROR;
}

@end
