#import "TH08IOSGLRenderer.h"

#include <stddef.h>
#include <stdint.h>
#include <math.h>
#include <string.h>
#include <map>
#include <new>

namespace {

struct RenderTargetResources {
    GLuint framebuffer;
    GLuint depthBuffer;
    GLsizei width;
    GLsizei height;
};

static const char *kVertexShader =
    "attribute vec3 a_position;\n"
    "uniform mat4 u_transform;\n"
    "attribute vec2 a_texcoord;\n"
    "attribute vec4 a_color;\n"
    "attribute float a_fog_coordinate;\n"
    "attribute vec4 a_specular;\n"
    "varying vec2 v_texcoord;\n"
    "varying vec4 v_color;\n"
    "varying float v_fog_coordinate;\n"
    "varying vec4 v_specular;\n"
    "void main() {\n"
    "  gl_Position = u_transform * vec4(a_position, 1.0);\n"
    "  v_texcoord = a_texcoord;\n"
    "  v_color = a_color;\n"
    "  v_fog_coordinate = a_fog_coordinate;\n"
    "  v_specular = a_specular;\n"
    "}\n";

static const char *kFragmentShader =
    "precision mediump float;\n"
    "uniform sampler2D u_texture;\n"
    "uniform float u_textured;\n"
    "uniform vec4 u_texture_factor;\n"
    "uniform int u_color_operation;\n"
    "uniform int u_color_argument1;\n"
    "uniform int u_color_argument2;\n"
    "uniform int u_alpha_operation;\n"
    "uniform int u_alpha_argument1;\n"
    "uniform int u_alpha_argument2;\n"
    "uniform float u_alpha_test_enabled;\n"
    "uniform int u_alpha_test_function;\n"
    "uniform float u_alpha_test_reference;\n"
    "uniform float u_fog_enabled;\n"
    "uniform vec4 u_fog_color;\n"
    "uniform float u_fog_start;\n"
    "uniform float u_fog_end;\n"
    "varying vec2 v_texcoord;\n"
    "varying vec4 v_color;\n"
    "varying float v_fog_coordinate;\n"
    "varying vec4 v_specular;\\n"
    "vec4 selectArgument(int argument, vec4 textureValue) {\n"
    "  if (argument == 0) return textureValue;\n"
    "  if (argument == 1) return v_color;\n"
    "  return u_texture_factor;\n"
    "}\n"
    "vec3 applyColorOperation(int operation, vec3 a, vec3 b) {\n"
    "  if (operation == 0) return a;\n"
    "  if (operation == 1) return b;\n"
    "  if (operation == 3) return a + b;\n"
    "  if (operation == 4) return a - b;\n"
    "  if (operation == 5) return a + b - vec3(0.5);\n"
    "  if (operation == 6) return min(a * b * 2.0, vec3(1.0));\n"
    "  if (operation == 7) return min(a * b * 4.0, vec3(1.0));\n"
    "  return a * b;\n"
    "}\n"
    "float applyAlphaOperation(int operation, float a, float b) {\n"
    "  if (operation == 0) return a;\n"
    "  if (operation == 1) return b;\n"
    "  if (operation == 3) return a + b;\n"
    "  if (operation == 4) return a - b;\n"
    "  if (operation == 5) return a + b - 0.5;\n"
    "  if (operation == 6) return min(a * b * 2.0, 1.0);\n"
    "  if (operation == 7) return min(a * b * 4.0, 1.0);\n"
    "  return a * b;\n"
    "}\n"
    "void main() {\n"
    "  vec4 texel = mix(vec4(1.0), texture2D(u_texture, v_texcoord), u_textured);\n"
    "  vec4 colorA = selectArgument(u_color_argument1, texel);\n"
    "  vec4 colorB = selectArgument(u_color_argument2, texel);\n"
    "  vec4 alphaA = selectArgument(u_alpha_argument1, texel);\n"
    "  vec4 alphaB = selectArgument(u_alpha_argument2, texel);\n"
    "  vec4 result = vec4(applyColorOperation(u_color_operation, colorA.rgb, colorB.rgb),\n"
    "                     applyAlphaOperation(u_alpha_operation, alphaA.a, alphaB.a));\n"
    "  result.rgb = min(result.rgb + v_specular.rgb, vec3(1.0));\n"
    "  if (u_fog_enabled > 0.5) {\n"
    "    float fogAmount = clamp((u_fog_end - v_fog_coordinate) / (u_fog_end - u_fog_start), 0.0, 1.0);\n"
    "    result.rgb = mix(u_fog_color.rgb, result.rgb, fogAmount);\n"
    "  }\n"
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
        glBindAttribLocation(program, 3, "a_fog_coordinate");
        glBindAttribLocation(program, 4, "a_specular");
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
    if (rowBytes < minimumRow || static_cast<size_t>(height) > SIZE_MAX / minimumRow)
        return false;
    return static_cast<size_t>(height - 1) <= (SIZE_MAX - minimumRow) / rowBytes;
}

bool IsValidBlendFactor(GLenum factor)
{
    switch (factor) {
    case GL_ZERO: case GL_ONE:
    case GL_SRC_COLOR: case GL_ONE_MINUS_SRC_COLOR:
    case GL_DST_COLOR: case GL_ONE_MINUS_DST_COLOR:
    case GL_SRC_ALPHA: case GL_ONE_MINUS_SRC_ALPHA:
    case GL_DST_ALPHA: case GL_ONE_MINUS_DST_ALPHA:
    case GL_SRC_ALPHA_SATURATE:
        return true;
    default:
        return false;
    }
}

bool IsValidBlendEquation(GLenum equation)
{
    return equation == GL_FUNC_ADD || equation == GL_FUNC_SUBTRACT ||
           equation == GL_FUNC_REVERSE_SUBTRACT;
}

bool IsValidTextureFilter(GLenum filter)
{
    return filter == GL_NEAREST || filter == GL_LINEAR;
}

bool IsValidTextureWrap(GLenum wrap)
{
    return wrap == GL_CLAMP_TO_EDGE || wrap == GL_REPEAT || wrap == GL_MIRRORED_REPEAT;
}

bool IsValidCompareFunction(GLenum function)
{
    switch (function) {
    case GL_NEVER: case GL_LESS: case GL_EQUAL: case GL_LEQUAL:
    case GL_GREATER: case GL_NOTEQUAL: case GL_GEQUAL: case GL_ALWAYS:
        return true;
    default:
        return false;
    }
}

bool IsValidPrimitive(TH08IOSRendererPrimitive primitive)
{
    switch (primitive) {
    case TH08IOSRendererPrimitivePoints:
    case TH08IOSRendererPrimitiveLines:
    case TH08IOSRendererPrimitiveLineStrip:
    case TH08IOSRendererPrimitiveTriangles:
    case TH08IOSRendererPrimitiveTriangleStrip:
    case TH08IOSRendererPrimitiveTriangleFan:
        return true;
    default:
        return false;
    }
}

} // namespace

@interface TH08IOSGLRenderer () {
    EAGLContext *_context;
    GLuint _defaultFramebuffer;
    GLint _defaultViewport[4];
    std::map<GLuint, RenderTargetResources> _renderTargets;
    GLuint _program;
    GLuint _vertexBuffer;
    GLint _samplerLocation;
    GLint _texturedLocation;
    GLint _transformLocation;
    GLint _alphaTestEnabledLocation;
    GLint _alphaTestFunctionLocation;
    GLint _alphaTestReferenceLocation;
    GLint _textureFactorLocation;
    GLint _colorOperationLocation;
    GLint _colorArgument1Location;
    GLint _colorArgument2Location;
    GLint _alphaOperationLocation;
    GLint _alphaArgument1Location;
    GLint _alphaArgument2Location;
    GLint _fogEnabledLocation;
    GLint _fogColorLocation;
    GLint _fogStartLocation;
    GLint _fogEndLocation;
    BOOL _fogEnabled;
    GLfloat _fogColor[4];
    GLfloat _fogStart;
    GLfloat _fogEnd;
    GLint _textureFactor[4];
    GLint _colorOperation;
    GLint _colorArgument1;
    GLint _colorArgument2;
    GLint _alphaOperation;
    GLint _alphaArgument1;
    GLint _alphaArgument2;
    GLfloat _transform[16];
    BOOL _alphaTestEnabled;
    GLint _alphaTestFunction;
    GLfloat _alphaTestReference;
    BOOL _blendingEnabled;
    BOOL _depthTestingEnabled;
    GLenum _depthCompareFunction;
    BOOL _scissorEnabled;
    GLint _scissorRect[4];
    BOOL _depthWriteEnabled;
    GLenum _sourceFactor;
    GLenum _destinationFactor;
    GLenum _blendEquation;
    GLboolean _colorWriteMask[4];
    GLenum _minificationFilter;
    GLenum _magnificationFilter;
    GLenum _wrapS;
    GLenum _wrapT;
    BOOL _hasViewport;
}
@end

@implementation TH08IOSGLRenderer

- (nullable instancetype)initWithCurrentContext
{
    self = [super init];
    if (self == nil)
        return nil;
    EAGLContext *context = [EAGLContext currentContext];
    if (context == nil)
        return nil;
    _context = context;
    GLint defaultFramebuffer = 0;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &defaultFramebuffer);
    _defaultFramebuffer = static_cast<GLuint>(defaultFramebuffer);
    glGetIntegerv(GL_VIEWPORT, _defaultViewport);

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
    _textureFactorLocation = glGetUniformLocation(_program, "u_texture_factor");
    _colorOperationLocation = glGetUniformLocation(_program, "u_color_operation");
    _colorArgument1Location = glGetUniformLocation(_program, "u_color_argument1");
    _colorArgument2Location = glGetUniformLocation(_program, "u_color_argument2");
    _alphaOperationLocation = glGetUniformLocation(_program, "u_alpha_operation");
    _alphaArgument1Location = glGetUniformLocation(_program, "u_alpha_argument1");
    _alphaArgument2Location = glGetUniformLocation(_program, "u_alpha_argument2");
    _fogEnabledLocation = glGetUniformLocation(_program, "u_fog_enabled");
    _fogColorLocation = glGetUniformLocation(_program, "u_fog_color");
    _fogStartLocation = glGetUniformLocation(_program, "u_fog_start");
    _fogEndLocation = glGetUniformLocation(_program, "u_fog_end");
    for (NSUInteger index = 0; index < 16; ++index)
        _transform[index] = (index % 5) == 0 ? 1.0f : 0.0f;
    _alphaTestEnabled = NO;
    _alphaTestFunction = 7;
    _alphaTestReference = 0.0f;
    _textureFactor[0] = _textureFactor[1] = _textureFactor[2] = _textureFactor[3] = 255;
    _colorOperation = TH08IOSRendererTextureOperationModulate;
    _colorArgument1 = TH08IOSRendererTextureArgumentTexture;
    _colorArgument2 = TH08IOSRendererTextureArgumentDiffuse;
    _alphaOperation = TH08IOSRendererTextureOperationModulate;
    _alphaArgument1 = TH08IOSRendererTextureArgumentTexture;
    _alphaArgument2 = TH08IOSRendererTextureArgumentDiffuse;
    _fogEnabled = NO;
    _fogColor[0] = _fogColor[1] = _fogColor[2] = 0.0f;
    _fogColor[3] = 1.0f;
    _fogStart = 0.0f;
    _fogEnd = 1.0f;
    _blendingEnabled = NO;
    _depthTestingEnabled = NO;
    _depthCompareFunction = GL_LESS;
    _scissorEnabled = NO;
    _scissorRect[0] = _scissorRect[1] = 0;
    _scissorRect[2] = _scissorRect[3] = 0;
    _depthWriteEnabled = YES;
    _sourceFactor = GL_SRC_ALPHA;
    _destinationFactor = GL_ONE_MINUS_SRC_ALPHA;
    _blendEquation = GL_FUNC_ADD;
    _colorWriteMask[0] = _colorWriteMask[1] = GL_TRUE;
    _colorWriteMask[2] = _colorWriteMask[3] = GL_TRUE;
    _minificationFilter = GL_LINEAR;
    _magnificationFilter = GL_LINEAR;
    _wrapS = GL_CLAMP_TO_EDGE;
    _wrapT = GL_CLAMP_TO_EDGE;
    _hasViewport = NO;
    return self;
}

- (void)dealloc
{
    // GL objects belong to the context that created them. Restore the caller's
    // context after deleting resources, even when teardown happens elsewhere.
    EAGLContext *previousContext = [EAGLContext currentContext];
    const BOOL changedContext = previousContext != _context;
    if (_context != nil && (!changedContext || [EAGLContext setCurrentContext:_context])) {
        for (std::map<GLuint, RenderTargetResources>::const_iterator it = _renderTargets.begin();
             it != _renderTargets.end(); ++it) {
            const GLuint texture = it->first;
            const RenderTargetResources &resources = it->second;
            if (resources.framebuffer != 0)
                glDeleteFramebuffers(1, &resources.framebuffer);
            if (resources.depthBuffer != 0)
                glDeleteRenderbuffers(1, &resources.depthBuffer);
            if (texture != 0)
                glDeleteTextures(1, &texture);
        }
        if (_vertexBuffer != 0)
            glDeleteBuffers(1, &_vertexBuffer);
        if (_program != 0)
            glDeleteProgram(_program);
        if (changedContext)
            [EAGLContext setCurrentContext:previousContext];
    }
}

- (BOOL)setViewportX:(GLint)x y:(GLint)y width:(GLsizei)width height:(GLsizei)height
{
    if ([EAGLContext currentContext] != _context || width <= 0 || height <= 0)
        return NO;
    GLint framebuffer = 0;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &framebuffer);
    if (static_cast<GLuint>(framebuffer) == _defaultFramebuffer) {
        _defaultViewport[0] = x;
        _defaultViewport[1] = y;
        _defaultViewport[2] = width;
        _defaultViewport[3] = height;
    }
    glViewport(x, y, width, height);
    _hasViewport = YES;
    return YES;
}

- (BOOL)setBlendingEnabled:(BOOL)enabled
             sourceFactor:(GLenum)sourceFactor
        destinationFactor:(GLenum)destinationFactor
{
    if ([EAGLContext currentContext] != _context ||
        !IsValidBlendFactor(sourceFactor) || !IsValidBlendFactor(destinationFactor))
        return NO;
    _blendingEnabled = enabled;
    _sourceFactor = sourceFactor;
    _destinationFactor = destinationFactor;
    return YES;
}

- (BOOL)setTextureStageColorOperation:(TH08IOSRendererTextureOperation)colorOperation
                      colorArgument1:(TH08IOSRendererTextureArgument)colorArgument1
                      colorArgument2:(TH08IOSRendererTextureArgument)colorArgument2
                        alphaOperation:(TH08IOSRendererTextureOperation)alphaOperation
                      alphaArgument1:(TH08IOSRendererTextureArgument)alphaArgument1
                      alphaArgument2:(TH08IOSRendererTextureArgument)alphaArgument2
{
    if ([EAGLContext currentContext] != _context ||
        colorOperation < TH08IOSRendererTextureOperationSelectArg1 ||
        colorOperation > TH08IOSRendererTextureOperationModulate4X ||
        alphaOperation < TH08IOSRendererTextureOperationSelectArg1 ||
        alphaOperation > TH08IOSRendererTextureOperationModulate4X ||
        colorArgument1 < TH08IOSRendererTextureArgumentTexture ||
        colorArgument1 > TH08IOSRendererTextureArgumentFactor ||
        colorArgument2 < TH08IOSRendererTextureArgumentTexture ||
        colorArgument2 > TH08IOSRendererTextureArgumentFactor ||
        alphaArgument1 < TH08IOSRendererTextureArgumentTexture ||
        alphaArgument1 > TH08IOSRendererTextureArgumentFactor ||
        alphaArgument2 < TH08IOSRendererTextureArgumentTexture ||
        alphaArgument2 > TH08IOSRendererTextureArgumentFactor)
        return NO;
    _colorOperation = colorOperation;
    _colorArgument1 = colorArgument1;
    _colorArgument2 = colorArgument2;
    _alphaOperation = alphaOperation;
    _alphaArgument1 = alphaArgument1;
    _alphaArgument2 = alphaArgument2;
    return YES;
}

- (void)setTextureFactorRed:(GLubyte)red green:(GLubyte)green blue:(GLubyte)blue alpha:(GLubyte)alpha
{
    if ([EAGLContext currentContext] != _context)
        return;
    _textureFactor[0] = red;
    _textureFactor[1] = green;
    _textureFactor[2] = blue;
    _textureFactor[3] = alpha;
}

- (BOOL)setFogEnabled:(BOOL)enabled colorRed:(GLfloat)red green:(GLfloat)green blue:(GLfloat)blue start:(GLfloat)start end:(GLfloat)end
{
    if ([EAGLContext currentContext] != _context ||
        !isfinite(red) || !isfinite(green) || !isfinite(blue) ||
        !isfinite(start) || !isfinite(end) || end <= start)
        return NO;
    _fogEnabled = enabled;
    _fogColor[0] = red < 0.0f ? 0.0f : (red > 1.0f ? 1.0f : red);
    _fogColor[1] = green < 0.0f ? 0.0f : (green > 1.0f ? 1.0f : green);
    _fogColor[2] = blue < 0.0f ? 0.0f : (blue > 1.0f ? 1.0f : blue);
    _fogColor[3] = 1.0f;
    _fogStart = start;
    _fogEnd = end;
    return YES;
}

- (BOOL)setBlendEquation:(GLenum)equation
{
    if ([EAGLContext currentContext] != _context || !IsValidBlendEquation(equation))
        return NO;
    _blendEquation = equation;
    return YES;
}

- (BOOL)setColorWriteMaskRed:(BOOL)red green:(BOOL)green blue:(BOOL)blue alpha:(BOOL)alpha
{
    if ([EAGLContext currentContext] != _context)
        return NO;
    _colorWriteMask[0] = red ? GL_TRUE : GL_FALSE;
    _colorWriteMask[1] = green ? GL_TRUE : GL_FALSE;
    _colorWriteMask[2] = blue ? GL_TRUE : GL_FALSE;
    _colorWriteMask[3] = alpha ? GL_TRUE : GL_FALSE;
    return YES;
}

- (BOOL)setTextureMinificationFilter:(GLenum)minificationFilter
                    magnificationFilter:(GLenum)magnificationFilter
                                  wrapS:(GLenum)wrapS
                                  wrapT:(GLenum)wrapT
{
    if ([EAGLContext currentContext] != _context ||
        !IsValidTextureFilter(minificationFilter) ||
        !IsValidTextureFilter(magnificationFilter) ||
        !IsValidTextureWrap(wrapS) || !IsValidTextureWrap(wrapT))
        return NO;
    _minificationFilter = minificationFilter;
    _magnificationFilter = magnificationFilter;
    _wrapS = wrapS;
    _wrapT = wrapT;
    return YES;
}

- (BOOL)setTransformMatrix:(const GLfloat *)columnMajorMatrix
{
    if ([EAGLContext currentContext] != _context || columnMajorMatrix == NULL)
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
    if ([EAGLContext currentContext] != _context)
        return NO;
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

- (BOOL)setDepthCompareFunction:(GLenum)compareFunction
{
    if ([EAGLContext currentContext] != _context || !IsValidCompareFunction(compareFunction))
        return NO;
    _depthCompareFunction = compareFunction;
    return YES;
}

- (BOOL)setScissorEnabled:(BOOL)enabled x:(GLint)x y:(GLint)y width:(GLsizei)width height:(GLsizei)height
{
    if ([EAGLContext currentContext] != _context ||
        (enabled && (width <= 0 || height <= 0)))
        return NO;
    _scissorEnabled = enabled;
    _scissorRect[0] = x;
    _scissorRect[1] = y;
    _scissorRect[2] = width;
    _scissorRect[3] = height;
    return YES;
}

- (void)setDepthTestingEnabled:(BOOL)enabled writeEnabled:(BOOL)writeEnabled
{
    if ([EAGLContext currentContext] != _context)
        return;
    _depthTestingEnabled = enabled;
    _depthWriteEnabled = writeEnabled;
}

- (void)applyDrawState
{
    if (_blendingEnabled) {
        glEnable(GL_BLEND);
        glBlendEquation(_blendEquation);
        glBlendFunc(_sourceFactor, _destinationFactor);
    } else {
        glDisable(GL_BLEND);
    }
    if (_depthTestingEnabled)
        glEnable(GL_DEPTH_TEST);
    else
        glDisable(GL_DEPTH_TEST);
    glDepthFunc(_depthCompareFunction);
    if (_scissorEnabled) {
        glEnable(GL_SCISSOR_TEST);
        glScissor(_scissorRect[0], _scissorRect[1], _scissorRect[2], _scissorRect[3]);
    } else {
        glDisable(GL_SCISSOR_TEST);
    }
    glDepthMask(_depthWriteEnabled ? GL_TRUE : GL_FALSE);
    glColorMask(_colorWriteMask[0], _colorWriteMask[1],
                _colorWriteMask[2], _colorWriteMask[3]);
}

- (void)clearRed:(GLfloat)red green:(GLfloat)green blue:(GLfloat)blue alpha:(GLfloat)alpha
           depth:(GLfloat)depth
{
    if ([EAGLContext currentContext] != _context)
        return;
    const GLboolean scissorWasEnabled = glIsEnabled(GL_SCISSOR_TEST);
    GLint previousScissor[4] = {0, 0, 0, 0};
    GLboolean previousDepthWrite = GL_TRUE;
    GLboolean previousColorMask[4] = {GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE};
    glGetIntegerv(GL_SCISSOR_BOX, previousScissor);
    glGetBooleanv(GL_DEPTH_WRITEMASK, &previousDepthWrite);
    glGetBooleanv(GL_COLOR_WRITEMASK, previousColorMask);
    if (scissorWasEnabled)
        glDisable(GL_SCISSOR_TEST);
    glDepthMask(GL_TRUE);
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glClearColor(red, green, blue, alpha);
    glClearDepthf(depth);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glDepthMask(previousDepthWrite);
    glColorMask(previousColorMask[0], previousColorMask[1],
                previousColorMask[2], previousColorMask[3]);
    if (scissorWasEnabled) {
        glScissor(previousScissor[0], previousScissor[1],
                  previousScissor[2], previousScissor[3]);
        glEnable(GL_SCISSOR_TEST);
    }
}

- (GLuint)createTextureWithRGBA8Pixels:(const void *)pixels
                                 width:(GLsizei)width
                                height:(GLsizei)height
                              rowBytes:(size_t)rowBytes
{
    if ([EAGLContext currentContext] != _context || pixels == NULL ||
        !IsValidTextureSize(width, height, rowBytes))
        return 0;

    // Attribute any GL error below to this upload, not to an earlier caller.
    while (glGetError() != GL_NO_ERROR) {}
    GLuint texture = 0;
    glGenTextures(1, &texture);
    if (texture == 0)
        return 0;

    GLint previousTexture = 0;
    GLint previousUnpackAlignment = 4;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTexture);
    glGetIntegerv(GL_UNPACK_ALIGNMENT, &previousUnpackAlignment);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, static_cast<GLint>(_minificationFilter));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, static_cast<GLint>(_magnificationFilter));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, static_cast<GLint>(_wrapS));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, static_cast<GLint>(_wrapT));

    const size_t packedRow = static_cast<size_t>(width) * 4u;
    const uint8_t *source = static_cast<const uint8_t *>(pixels);
    if (rowBytes == packedRow) {
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0,
                     GL_RGBA, GL_UNSIGNED_BYTE, source);
    } else {
        NSMutableData *packed = [NSMutableData dataWithLength:packedRow * static_cast<size_t>(height)];
        uint8_t *destination = static_cast<uint8_t *>(packed.mutableBytes);
        if (destination == NULL) {
            glBindTexture(GL_TEXTURE_2D, static_cast<GLuint>(previousTexture));
            glDeleteTextures(1, &texture);
            return 0;
        }
        for (GLsizei row = 0; row < height; ++row)
            memcpy(destination + static_cast<size_t>(row) * packedRow,
                   source + static_cast<size_t>(row) * rowBytes, packedRow);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0,
                     GL_RGBA, GL_UNSIGNED_BYTE, destination);
    }
    const GLenum uploadError = glGetError();
    glPixelStorei(GL_UNPACK_ALIGNMENT, previousUnpackAlignment);
    glBindTexture(GL_TEXTURE_2D, static_cast<GLuint>(previousTexture));
    if (uploadError != GL_NO_ERROR) {
        glDeleteTextures(1, &texture);
        return 0;
    }
    return texture;
}

- (GLuint)createRenderTargetWithWidth:(GLsizei)width height:(GLsizei)height
{
    if ([EAGLContext currentContext] != _context || width <= 0 || height <= 0)
        return 0;
    GLint previousTexture = 0;
    GLint previousFramebuffer = 0;
    GLint previousRenderbuffer = 0;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTexture);
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &previousFramebuffer);
    glGetIntegerv(GL_RENDERBUFFER_BINDING, &previousRenderbuffer);
    while (glGetError() != GL_NO_ERROR) {}

    GLuint texture = 0;
    GLuint framebuffer = 0;
    GLuint depthBuffer = 0;
    glGenTextures(1, &texture);
    if (texture == 0)
        return 0;
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, NULL);

    glGenFramebuffers(1, &framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    glGenRenderbuffers(1, &depthBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, depthBuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, width, height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthBuffer);
    const GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    const GLenum error = glGetError();

    glBindFramebuffer(GL_FRAMEBUFFER, static_cast<GLuint>(previousFramebuffer));
    glBindRenderbuffer(GL_RENDERBUFFER, static_cast<GLuint>(previousRenderbuffer));
    glBindTexture(GL_TEXTURE_2D, static_cast<GLuint>(previousTexture));
    if (status != GL_FRAMEBUFFER_COMPLETE || error != GL_NO_ERROR || framebuffer == 0 || depthBuffer == 0) {
        if (framebuffer != 0) glDeleteFramebuffers(1, &framebuffer);
        if (depthBuffer != 0) glDeleteRenderbuffers(1, &depthBuffer);
        if (texture != 0) glDeleteTextures(1, &texture);
        return 0;
    }

    RenderTargetResources resources;
    resources.framebuffer = framebuffer;
    resources.depthBuffer = depthBuffer;
    resources.width = width;
    resources.height = height;
    try {
        _renderTargets.insert(std::make_pair(texture, resources));
    } catch (const std::bad_alloc &) {
        glDeleteFramebuffers(1, &framebuffer);
        glDeleteRenderbuffers(1, &depthBuffer);
        glDeleteTextures(1, &texture);
        return 0;
    }
    return texture;
}

- (BOOL)bindRenderTargetTexture:(GLuint)texture
{
    if ([EAGLContext currentContext] != _context)
        return NO;
    if (texture == 0) {
        while (glGetError() != GL_NO_ERROR) {}
        glBindFramebuffer(GL_FRAMEBUFFER, _defaultFramebuffer);
        glViewport(_defaultViewport[0], _defaultViewport[1],
                   _defaultViewport[2], _defaultViewport[3]);
        return glGetError() == GL_NO_ERROR;
    }
    std::map<GLuint, RenderTargetResources>::const_iterator it = _renderTargets.find(texture);
    if (it == _renderTargets.end())
        return NO;
    while (glGetError() != GL_NO_ERROR) {}
    glBindFramebuffer(GL_FRAMEBUFFER, it->second.framebuffer);
    glViewport(0, 0, it->second.width, it->second.height);
    return glGetError() == GL_NO_ERROR;
}

- (nullable NSData *)copyCurrentFramebufferRGBA8PixelsWithWidth:(GLsizei)width
                                                         height:(GLsizei)height
{
    if ([EAGLContext currentContext] != _context || width <= 0 || height <= 0)
        return nil;
    const size_t rowBytes = static_cast<size_t>(width) * 4u;
    if (rowBytes / 4u != static_cast<size_t>(width) ||
        static_cast<size_t>(height) > SIZE_MAX / rowBytes ||
        rowBytes * static_cast<size_t>(height) > static_cast<size_t>(PTRDIFF_MAX))
        return nil;

    while (glGetError() != GL_NO_ERROR) {}
    GLint previousPackAlignment = 4;
    glGetIntegerv(GL_PACK_ALIGNMENT, &previousPackAlignment);
    NSMutableData *pixels = [NSMutableData dataWithLength:rowBytes * static_cast<size_t>(height)];
    if (pixels == nil || pixels.mutableBytes == NULL)
        return nil;
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels.mutableBytes);
    const GLenum readError = glGetError();
    glPixelStorei(GL_PACK_ALIGNMENT, previousPackAlignment);
    if (readError != GL_NO_ERROR)
        return nil;
    return [pixels copy];
}

- (void)deleteTexture:(GLuint)texture
{
    if (texture == 0 || [EAGLContext currentContext] != _context)
        return;
    std::map<GLuint, RenderTargetResources>::iterator it = _renderTargets.find(texture);
    if (it != _renderTargets.end()) {
        GLint currentFramebuffer = 0;
        glGetIntegerv(GL_FRAMEBUFFER_BINDING, &currentFramebuffer);
        if (static_cast<GLuint>(currentFramebuffer) == it->second.framebuffer) {
            glBindFramebuffer(GL_FRAMEBUFFER, _defaultFramebuffer);
            glViewport(_defaultViewport[0], _defaultViewport[1],
                       _defaultViewport[2], _defaultViewport[3]);
        }
        if (it->second.framebuffer != 0)
            glDeleteFramebuffers(1, &it->second.framebuffer);
        if (it->second.depthBuffer != 0)
            glDeleteRenderbuffers(1, &it->second.depthBuffer);
        _renderTargets.erase(it);
    }
    glDeleteTextures(1, &texture);
}

- (BOOL)drawVertices:(const TH08IOSRendererVertex *)vertices
               count:(GLsizei)count
           primitive:(TH08IOSRendererPrimitive)primitive
             texture:(GLuint)texture
{
    if ([EAGLContext currentContext] != _context || !_hasViewport ||
        vertices == NULL || count <= 0 || !IsValidPrimitive(primitive) ||
        _program == 0 || _vertexBuffer == 0)
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
    glUniform4f(_textureFactorLocation,
                _textureFactor[0] / 255.0f, _textureFactor[1] / 255.0f,
                _textureFactor[2] / 255.0f, _textureFactor[3] / 255.0f);
    glUniform1i(_colorOperationLocation, _colorOperation);
    glUniform1i(_colorArgument1Location, _colorArgument1);
    glUniform1i(_colorArgument2Location, _colorArgument2);
    glUniform1i(_alphaOperationLocation, _alphaOperation);
    glUniform1i(_alphaArgument1Location, _alphaArgument1);
    glUniform1i(_alphaArgument2Location, _alphaArgument2);
    glUniform1f(_fogEnabledLocation, _fogEnabled ? 1.0f : 0.0f);
    glUniform4f(_fogColorLocation, _fogColor[0], _fogColor[1], _fogColor[2], _fogColor[3]);
    glUniform1f(_fogStartLocation, _fogStart);
    glUniform1f(_fogEndLocation, _fogEnd);
    [self applyDrawState];
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texture);
    if (texture != 0) {
        // D3D8 sampler state is device state and must affect already-created
        // textures as well as textures created after the state change.
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, static_cast<GLint>(_minificationFilter));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, static_cast<GLint>(_magnificationFilter));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, static_cast<GLint>(_wrapS));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, static_cast<GLint>(_wrapT));
    }
    glUniform1i(_samplerLocation, 0);
    glUniform1f(_texturedLocation, texture != 0 ? 1.0f : 0.0f);

    glBindBuffer(GL_ARRAY_BUFFER, _vertexBuffer);
    glBufferData(GL_ARRAY_BUFFER, static_cast<GLsizeiptr>(vertexBytes),
                 vertices, GL_STREAM_DRAW);
    const GLsizei stride = static_cast<GLsizei>(sizeof(TH08IOSRendererVertex));
    glEnableVertexAttribArray(0);
    glEnableVertexAttribArray(1);
    glEnableVertexAttribArray(2);
    glEnableVertexAttribArray(3);
    glEnableVertexAttribArray(4);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride,
                          reinterpret_cast<const GLvoid *>(offsetof(TH08IOSRendererVertex, x)));
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, stride,
                          reinterpret_cast<const GLvoid *>(offsetof(TH08IOSRendererVertex, u)));
    glVertexAttribPointer(2, 4, GL_UNSIGNED_BYTE, GL_TRUE, stride,
                          reinterpret_cast<const GLvoid *>(offsetof(TH08IOSRendererVertex, red)));
    glVertexAttribPointer(3, 1, GL_FLOAT, GL_FALSE, stride,
                          reinterpret_cast<const GLvoid *>(offsetof(TH08IOSRendererVertex, fogCoordinate)));
    glVertexAttribPointer(4, 4, GL_UNSIGNED_BYTE, GL_TRUE, stride,
                          reinterpret_cast<const GLvoid *>(offsetof(TH08IOSRendererVertex, specularRed)));
    glDrawArrays(static_cast<GLenum>(primitive), 0, count);
    glDisableVertexAttribArray(0);
    glDisableVertexAttribArray(1);
    glDisableVertexAttribArray(2);
    glDisableVertexAttribArray(3);
    glDisableVertexAttribArray(4);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    return glGetError() == GL_NO_ERROR;
}

@end
