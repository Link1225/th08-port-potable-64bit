#import <XCTest/XCTest.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>

#import "../Renderer/TH08IOSGLRenderer.h"

@interface TH08IOSGLRendererTests : XCTestCase
@property(nonatomic, strong) EAGLContext *context;
@property(nonatomic, strong) TH08IOSGLRenderer *renderer;

@end

@implementation TH08IOSGLRendererTests

- (void)setUp
{
    [super setUp];
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    XCTAssertNotNil(self.context);
    XCTAssertTrue([EAGLContext setCurrentContext:self.context]);
    self.renderer = [[TH08IOSGLRenderer alloc] initWithCurrentContext];
    XCTAssertNotNil(self.renderer);
}

- (void)tearDown
{
    self.renderer = nil;
    [EAGLContext setCurrentContext:nil];
    self.context = nil;
    [super tearDown];
}

- (void)testRenderTargetClearAndRGBAReadback
{
    const GLuint target = [self.renderer createRenderTargetWithWidth:8 height:8];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);

    [self.renderer clearRed:1.0f green:0.0f blue:0.0f alpha:1.0f depth:1.0f];
    NSData *pixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(pixels);
    XCTAssertEqual(pixels.length, (NSUInteger)(8u * 8u * 4u));

    const uint8_t *bytes = (const uint8_t *)pixels.bytes;
    XCTAssertEqual(bytes[0], (uint8_t)255);
    XCTAssertEqual(bytes[1], (uint8_t)0);
    XCTAssertEqual(bytes[2], (uint8_t)0);
    XCTAssertEqual(bytes[3], (uint8_t)255);

    XCTAssertTrue([self.renderer bindRenderTargetTexture:0]);
    [self.renderer deleteTexture:target];
}

- (void)testRenderTargetSwitchAndDeleteRestoreDefaultFramebuffer
{
    GLint originalFramebuffer = 0;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &originalFramebuffer);

    const GLuint target = [self.renderer createRenderTargetWithWidth:4 height:4];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);

    GLint targetFramebuffer = 0;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &targetFramebuffer);
    XCTAssertNotEqual(targetFramebuffer, originalFramebuffer);

    [self.renderer deleteTexture:target];
    GLint restoredFramebuffer = -1;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &restoredFramebuffer);
    XCTAssertEqual(restoredFramebuffer, originalFramebuffer);
}

- (void)testRejectsInvalidSamplerAndBlendState
{
    XCTAssertFalse([self.renderer setTextureMinificationFilter:GL_LINEAR_MIPMAP_LINEAR
                                             magnificationFilter:GL_LINEAR
                                                           wrapS:GL_CLAMP_TO_EDGE
                                                           wrapT:GL_CLAMP_TO_EDGE]);
    XCTAssertFalse([self.renderer setTextureMinificationFilter:GL_LINEAR
                                             magnificationFilter:GL_LINEAR
                                                           wrapS:0xDEAD
                                                           wrapT:GL_CLAMP_TO_EDGE]);
    XCTAssertFalse([self.renderer setBlendingEnabled:YES sourceFactor:0xDEAD
                                    destinationFactor:GL_ONE_MINUS_SRC_ALPHA]);
    XCTAssertTrue([self.renderer setTextureMinificationFilter:GL_NEAREST
                                            magnificationFilter:GL_LINEAR
                                                          wrapS:GL_REPEAT
                                                          wrapT:GL_CLAMP_TO_EDGE]);
    XCTAssertTrue([self.renderer setBlendingEnabled:YES sourceFactor:GL_SRC_ALPHA
                                   destinationFactor:GL_ONE_MINUS_SRC_ALPHA]);
}

- (void)testDrawsUntexturedColoredTriangleIntoRenderTarget
{
    const GLuint target = [self.renderer createRenderTargetWithWidth:8 height:8];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:8 height:8]);
    [self.renderer clearRed:0.0f green:0.0f blue:0.0f alpha:1.0f depth:1.0f];

    TH08IOSRendererVertex vertices[3] = {
        {-1.0f, -1.0f, 0.0f, 0.0f, 0.0f, 255, 0, 0, 255},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255, 0, 0, 255},
        { 0.0f,  1.0f, 0.0f, 0.5f, 1.0f, 255, 0, 0, 255}
    };
    XCTAssertTrue([self.renderer drawVertices:vertices count:3
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:0]);

    NSData *pixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(pixels);
    const uint8_t *bytes = (const uint8_t *)pixels.bytes;
    const NSUInteger center = (NSUInteger)(4u * 8u + 4u) * 4u;
    XCTAssertGreaterThan(bytes[center], (uint8_t)200);
    XCTAssertLessThan(bytes[center + 1], (uint8_t)20);
    XCTAssertLessThan(bytes[center + 2], (uint8_t)20);
    XCTAssertEqual(bytes[center + 3], (uint8_t)255);

    [self.renderer deleteTexture:target];
}

- (void)testUploadsAndSamplesRGBA8Texture
{
    const uint8_t texel[4] = {0, 255, 0, 255};
    const GLuint texture = [self.renderer createTextureWithRGBA8Pixels:texel
                                                                  width:1
                                                                 height:1
                                                               rowBytes:4];
    XCTAssertNotEqual(texture, 0u);

    const GLuint target = [self.renderer createRenderTargetWithWidth:8 height:8];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:8 height:8]);
    [self.renderer clearRed:0.0f green:0.0f blue:0.0f alpha:1.0f depth:1.0f];

    TH08IOSRendererVertex vertices[6] = {
        {-1.0f, -1.0f, 0.0f, 0.0f, 0.0f, 255, 255, 255, 255},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255, 255, 255, 255},
        {-1.0f,  1.0f, 0.0f, 0.0f, 1.0f, 255, 255, 255, 255},
        {-1.0f,  1.0f, 0.0f, 0.0f, 1.0f, 255, 255, 255, 255},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255, 255, 255, 255},
        { 1.0f,  1.0f, 0.0f, 1.0f, 1.0f, 255, 255, 255, 255}
    };
    XCTAssertTrue([self.renderer drawVertices:vertices count:6
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:texture]);

    NSData *pixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(pixels);
    const uint8_t *bytes = (const uint8_t *)pixels.bytes;
    const NSUInteger center = (NSUInteger)(4u * 8u + 4u) * 4u;
    XCTAssertLessThan(bytes[center], (uint8_t)20);
    XCTAssertGreaterThan(bytes[center + 1], (uint8_t)200);
    XCTAssertLessThan(bytes[center + 2], (uint8_t)20);
    XCTAssertEqual(bytes[center + 3], (uint8_t)255);

    [self.renderer deleteTexture:target];
    [self.renderer deleteTexture:texture];
}


- (void)testAlphaTestAndTransformMatrix
{
    const GLuint target = [self.renderer createRenderTargetWithWidth:8 height:8];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:8 height:8]);
    [self.renderer clearRed:0.0f green:0.0f blue:1.0f alpha:1.0f depth:1.0f];

    TH08IOSRendererVertex vertices[6] = {
        {-1.0f, -1.0f, 0.0f, 0.0f, 0.0f, 255, 0, 0, 64},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255, 0, 0, 64},
        {-1.0f,  1.0f, 0.0f, 0.0f, 1.0f, 255, 0, 0, 64},
        {-1.0f,  1.0f, 0.0f, 0.0f, 1.0f, 255, 0, 0, 64},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255, 0, 0, 64},
        { 1.0f,  1.0f, 0.0f, 1.0f, 1.0f, 255, 0, 0, 64}
    };
    XCTAssertTrue([self.renderer setAlphaTestEnabled:YES compareFunction:GL_GREATER reference:0.5f]);
    XCTAssertTrue([self.renderer drawVertices:vertices count:6
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:0]);

    NSData *discardedPixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(discardedPixels);
    const uint8_t *discarded = (const uint8_t *)discardedPixels.bytes;
    const NSUInteger center = (NSUInteger)(4u * 8u + 4u) * 4u;
    XCTAssertLessThan(discarded[center], (uint8_t)20);
    XCTAssertGreaterThan(discarded[center + 2], (uint8_t)200);

    const GLfloat translated[16] = {
        1.0f, 0.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 1.0f, 0.0f,
        0.5f, 0.0f, 0.0f, 1.0f
    };
    for (NSUInteger index = 0; index < 6; ++index)
        vertices[index].alpha = 255;
    XCTAssertTrue([self.renderer setTransformMatrix:translated]);
    XCTAssertTrue([self.renderer setAlphaTestEnabled:NO compareFunction:GL_ALWAYS reference:0.0f]);
    XCTAssertTrue([self.renderer drawVertices:vertices count:6
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:0]);

    NSData *transformedPixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(transformedPixels);
    const uint8_t *transformed = (const uint8_t *)transformedPixels.bytes;
    const NSUInteger leftPixel = (NSUInteger)(4u * 8u) * 4u;
    XCTAssertLessThan(transformed[leftPixel], (uint8_t)20);
    XCTAssertGreaterThan(transformed[leftPixel + 2], (uint8_t)200);
    XCTAssertGreaterThan(transformed[center], (uint8_t)200);
    XCTAssertLessThan(transformed[center + 2], (uint8_t)20);

    [self.renderer deleteTexture:target];
}

- (void)testTextureUploadHonorsPaddedSourceRows
{
    const uint8_t paddedPixels[16] = {
        255, 0, 0, 255, 0xAA, 0xAA, 0xAA, 0xAA,
        0, 255, 0, 255, 0xBB, 0xBB, 0xBB, 0xBB
    };
    const GLuint texture = [self.renderer createTextureWithRGBA8Pixels:paddedPixels
                                                                  width:1
                                                                 height:2
                                                               rowBytes:8];
    XCTAssertNotEqual(texture, 0u);
    const GLuint target = [self.renderer createRenderTargetWithWidth:4 height:4];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:4 height:4]);
    [self.renderer clearRed:0.0f green:0.0f blue:0.0f alpha:1.0f depth:1.0f];

    TH08IOSRendererVertex vertices[6] = {
        {-1.0f, -1.0f, 0.0f, 0.0f, 0.0f, 255, 255, 255, 255},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255, 255, 255, 255},
        {-1.0f,  1.0f, 0.0f, 0.0f, 1.0f, 255, 255, 255, 255},
        {-1.0f,  1.0f, 0.0f, 0.0f, 1.0f, 255, 255, 255, 255},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255, 255, 255, 255},
        { 1.0f,  1.0f, 0.0f, 1.0f, 1.0f, 255, 255, 255, 255}
    };
    XCTAssertTrue([self.renderer setTextureMinificationFilter:GL_NEAREST
                                            magnificationFilter:GL_NEAREST
                                                          wrapS:GL_CLAMP_TO_EDGE
                                                          wrapT:GL_CLAMP_TO_EDGE]);
    XCTAssertTrue([self.renderer drawVertices:vertices count:6
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:texture]);
    NSData *pixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:4 height:4];
    XCTAssertNotNil(pixels);
    const uint8_t *bytes = (const uint8_t *)pixels.bytes;
    const NSUInteger lowerCenter = (NSUInteger)(1u * 4u + 2u) * 4u;
    XCTAssertGreaterThan(bytes[lowerCenter], (uint8_t)200);
    XCTAssertLessThan(bytes[lowerCenter + 1], (uint8_t)20);
    XCTAssertLessThan(bytes[lowerCenter + 2], (uint8_t)20);

    [self.renderer deleteTexture:target];
    [self.renderer deleteTexture:texture];
}


- (void)testBlendAndDepthTesting
{
    const GLuint target = [self.renderer createRenderTargetWithWidth:8 height:8];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:8 height:8]);
    [self.renderer clearRed:0.0f green:0.0f blue:1.0f alpha:1.0f depth:1.0f];

    TH08IOSRendererVertex vertices[6] = {
        {-1.0f, -1.0f, 0.0f, 0.0f, 0.0f, 255, 0, 0, 128},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255, 0, 0, 128},
        {-1.0f,  1.0f, 0.0f, 0.0f, 1.0f, 255, 0, 0, 128},
        {-1.0f,  1.0f, 0.0f, 0.0f, 1.0f, 255, 0, 0, 128},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255, 0, 0, 128},
        { 1.0f,  1.0f, 0.0f, 1.0f, 1.0f, 255, 0, 0, 128}
    };
    XCTAssertTrue([self.renderer setBlendingEnabled:YES
                                        sourceFactor:GL_SRC_ALPHA
                                   destinationFactor:GL_ONE_MINUS_SRC_ALPHA]);
    [self.renderer setDepthTestingEnabled:YES writeEnabled:YES];
    XCTAssertTrue([self.renderer drawVertices:vertices count:6
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:0]);

    for (NSUInteger index = 0; index < 6; ++index) {
        vertices[index].z = 0.5f;
        vertices[index].red = 0;
        vertices[index].green = 255;
        vertices[index].alpha = 255;
    }
    XCTAssertTrue([self.renderer setBlendingEnabled:NO
                                        sourceFactor:GL_ONE
                                   destinationFactor:GL_ZERO]);
    XCTAssertTrue([self.renderer drawVertices:vertices count:6
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:0]);

    NSData *pixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(pixels);
    const uint8_t *bytes = (const uint8_t *)pixels.bytes;
    const NSUInteger center = (NSUInteger)(4u * 8u + 4u) * 4u;
    XCTAssertGreaterThan(bytes[center], (uint8_t)110);
    XCTAssertLessThan(bytes[center], (uint8_t)145);
    XCTAssertLessThan(bytes[center + 1], (uint8_t)20);
    XCTAssertGreaterThan(bytes[center + 2], (uint8_t)110);
    XCTAssertLessThan(bytes[center + 2], (uint8_t)145);

    [self.renderer deleteTexture:target];
}

- (void)testRenderTargetRestoresDefaultViewport
{
    XCTAssertTrue([self.renderer setViewportX:2 y:3 width:7 height:6]);
    const GLuint target = [self.renderer createRenderTargetWithWidth:4 height:4];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:4 height:4]);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:0]);

    GLint viewport[4] = {0, 0, 0, 0};
    glGetIntegerv(GL_VIEWPORT, viewport);
    XCTAssertEqual(viewport[0], 2);
    XCTAssertEqual(viewport[1], 3);
    XCTAssertEqual(viewport[2], 7);
    XCTAssertEqual(viewport[3], 6);

    [self.renderer deleteTexture:target];
}


- (void)testDepthCompareFunctionControlsDepthRejection
{
    const GLuint target = [self.renderer createRenderTargetWithWidth:8 height:8];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:8 height:8]);
    [self.renderer clearRed:0.0f green:0.0f blue:0.0f alpha:1.0f depth:1.0f];
    [self.renderer setDepthTestingEnabled:YES writeEnabled:YES];

    TH08IOSRendererVertex vertices[6] = {
        {-1.0f, -1.0f, 0.5f, 0.0f, 0.0f, 0, 255, 0, 255},
        { 1.0f, -1.0f, 0.5f, 1.0f, 0.0f, 0, 255, 0, 255},
        {-1.0f,  1.0f, 0.5f, 0.0f, 1.0f, 0, 255, 0, 255},
        {-1.0f,  1.0f, 0.5f, 0.0f, 1.0f, 0, 255, 0, 255},
        { 1.0f, -1.0f, 0.5f, 1.0f, 0.0f, 0, 255, 0, 255},
        { 1.0f,  1.0f, 0.5f, 1.0f, 1.0f, 0, 255, 0, 255}
    };
    XCTAssertTrue([self.renderer setDepthCompareFunction:GL_GREATER]);
    XCTAssertTrue([self.renderer drawVertices:vertices count:6
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:0]);

    XCTAssertTrue([self.renderer setDepthCompareFunction:GL_ALWAYS]);
    XCTAssertTrue([self.renderer drawVertices:vertices count:6
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:0]);

    for (NSUInteger index = 0; index < 6; ++index) {
        vertices[index].z = -0.5f;
        vertices[index].red = 255;
        vertices[index].green = 0;
    }
    XCTAssertTrue([self.renderer setDepthCompareFunction:GL_NEVER]);
    XCTAssertTrue([self.renderer drawVertices:vertices count:6
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:0]);

    NSData *pixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(pixels);
    const uint8_t *bytes = (const uint8_t *)pixels.bytes;
    const NSUInteger center = (NSUInteger)(4u * 8u + 4u) * 4u;
    XCTAssertLessThan(bytes[center], (uint8_t)20);
    XCTAssertGreaterThan(bytes[center + 1], (uint8_t)200);
    XCTAssertLessThan(bytes[center + 2], (uint8_t)20);
    XCTAssertFalse([self.renderer setDepthCompareFunction:0xDEAD]);

    [self.renderer deleteTexture:target];
}

- (void)testRendererStateMutationsRequireOwningContext
{
    EAGLContext *otherContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    XCTAssertNotNil(otherContext);
    XCTAssertTrue([EAGLContext setCurrentContext:otherContext]);

    const GLfloat identity[16] = {
        1.0f, 0.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, 0.0f, 1.0f
    };
    XCTAssertFalse([self.renderer setBlendingEnabled:YES
                                         sourceFactor:GL_SRC_ALPHA
                                    destinationFactor:GL_ONE_MINUS_SRC_ALPHA]);
    XCTAssertFalse([self.renderer setTextureMinificationFilter:GL_NEAREST
                                            magnificationFilter:GL_NEAREST
                                                          wrapS:GL_CLAMP_TO_EDGE
                                                          wrapT:GL_CLAMP_TO_EDGE]);
    XCTAssertFalse([self.renderer setTransformMatrix:identity]);
    XCTAssertFalse([self.renderer setAlphaTestEnabled:YES
                                       compareFunction:GL_ALWAYS
                                             reference:0.5f]);
    XCTAssertFalse([self.renderer setDepthCompareFunction:GL_ALWAYS]);

    XCTAssertTrue([EAGLContext setCurrentContext:self.context]);
    XCTAssertTrue([self.renderer setDepthCompareFunction:GL_LESS]);
}


- (void)testScissorClipsDrawsAndClearIgnoresScissor
{
    const GLuint target = [self.renderer createRenderTargetWithWidth:8 height:8];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:8 height:8]);
    [self.renderer clearRed:0.0f green:0.0f blue:0.0f alpha:1.0f depth:1.0f];
    XCTAssertTrue([self.renderer setScissorEnabled:YES x:2 y:2 width:3 height:3]);
    XCTAssertFalse([self.renderer setScissorEnabled:YES x:0 y:0 width:0 height:3]);

    TH08IOSRendererVertex vertices[6] = {
        {-1.0f, -1.0f, 0.0f, 0.0f, 0.0f, 255, 0, 0, 255},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255, 0, 0, 255},
        {-1.0f,  1.0f, 0.0f, 0.0f, 1.0f, 255, 0, 0, 255},
        {-1.0f,  1.0f, 0.0f, 0.0f, 1.0f, 255, 0, 0, 255},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255, 0, 0, 255},
        { 1.0f,  1.0f, 0.0f, 1.0f, 1.0f, 255, 0, 0, 255}
    };
    XCTAssertTrue([self.renderer drawVertices:vertices count:6
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:0]);
    NSData *clippedPixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(clippedPixels);
    const uint8_t *clipped = (const uint8_t *)clippedPixels.bytes;
    const NSUInteger inside = (NSUInteger)(3u * 8u + 3u) * 4u;
    const NSUInteger outside = (NSUInteger)(3u * 8u + 6u) * 4u;
    XCTAssertGreaterThan(clipped[inside], (uint8_t)200);
    XCTAssertLessThan(clipped[outside], (uint8_t)20);

    [self.renderer clearRed:0.0f green:0.0f blue:1.0f alpha:1.0f depth:1.0f];
    NSData *clearedPixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(clearedPixels);
    const uint8_t *cleared = (const uint8_t *)clearedPixels.bytes;
    XCTAssertLessThan(cleared[outside], (uint8_t)20);
    XCTAssertGreaterThan(cleared[outside + 2], (uint8_t)200);
    XCTAssertTrue([self.renderer setScissorEnabled:NO x:0 y:0 width:0 height:0]);

    [self.renderer deleteTexture:target];
}


- (void)testColorWriteMaskAndClearRestoreAllChannels
{
    const GLuint target = [self.renderer createRenderTargetWithWidth:8 height:8];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:8 height:8]);
    [self.renderer clearRed:0.0f green:0.0f blue:0.0f alpha:1.0f depth:1.0f];
    XCTAssertTrue([self.renderer setColorWriteMaskRed:NO green:YES blue:NO alpha:NO]);
    TH08IOSRendererVertex vertices[3] = {
        {-1.0f, -1.0f, 0.0f, 0.0f, 0.0f, 255, 255, 255, 255},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255, 255, 255, 255},
        { 0.0f,  1.0f, 0.0f, 0.5f, 1.0f, 255, 255, 255, 255}
    };
    XCTAssertTrue([self.renderer drawVertices:vertices count:3
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:0]);
    NSData *drawn = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(drawn);
    const uint8_t *drawnBytes = (const uint8_t *)drawn.bytes;
    const NSUInteger center = (NSUInteger)(4u * 8u + 4u) * 4u;
    XCTAssertLessThan(drawnBytes[center], (uint8_t)20);
    XCTAssertGreaterThan(drawnBytes[center + 1], (uint8_t)200);
    XCTAssertLessThan(drawnBytes[center + 2], (uint8_t)20);
    XCTAssertEqual(drawnBytes[center + 3], (uint8_t)255);
    [self.renderer clearRed:0.0f green:0.0f blue:1.0f alpha:1.0f depth:1.0f];
    NSData *cleared = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(cleared);
    const uint8_t *clearBytes = (const uint8_t *)cleared.bytes;
    XCTAssertEqual(clearBytes[center], (uint8_t)0);
    XCTAssertEqual(clearBytes[center + 1], (uint8_t)0);
    XCTAssertEqual(clearBytes[center + 2], (uint8_t)255);
    XCTAssertEqual(clearBytes[center + 3], (uint8_t)255);
    XCTAssertTrue([self.renderer setColorWriteMaskRed:YES green:YES blue:YES alpha:YES]);
    [self.renderer deleteTexture:target];
}

- (void)testReverseSubtractBlendEquation
{
    const GLuint target = [self.renderer createRenderTargetWithWidth:8 height:8];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:8 height:8]);
    [self.renderer clearRed:0.0f green:0.0f blue:1.0f alpha:1.0f depth:1.0f];
    XCTAssertTrue([self.renderer setBlendingEnabled:YES sourceFactor:GL_ONE
                                   destinationFactor:GL_SRC_ALPHA]);
    XCTAssertTrue([self.renderer setBlendEquation:GL_FUNC_REVERSE_SUBTRACT]);
    XCTAssertFalse([self.renderer setBlendEquation:0xDEAD]);
    TH08IOSRendererVertex vertices[3] = {
        {-1.0f, -1.0f, 0.0f, 0.0f, 0.0f, 255, 0, 0, 128},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255, 0, 0, 128},
        { 0.0f,  1.0f, 0.0f, 0.5f, 1.0f, 255, 0, 0, 128}
    };
    XCTAssertTrue([self.renderer drawVertices:vertices count:3
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:0]);
    NSData *pixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(pixels);
    const uint8_t *bytes = (const uint8_t *)pixels.bytes;
    const NSUInteger center = (NSUInteger)(4u * 8u + 4u) * 4u;
    XCTAssertLessThan(bytes[center], (uint8_t)20);
    XCTAssertLessThan(bytes[center + 1], (uint8_t)20);
    XCTAssertGreaterThan(bytes[center + 2], (uint8_t)100);
    XCTAssertLessThan(bytes[center + 2], (uint8_t)170);
    [self.renderer setBlendEquation:GL_FUNC_ADD];
    [self.renderer setBlendingEnabled:NO sourceFactor:GL_SRC_ALPHA
                      destinationFactor:GL_ONE_MINUS_SRC_ALPHA];
    [self.renderer deleteTexture:target];
}


- (void)testTextureStageCanSelectTextureFactor
{
    const GLuint target = [self.renderer createRenderTargetWithWidth:8 height:8];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:8 height:8]);
    [self.renderer clearRed:0.0f green:0.0f blue:0.0f alpha:0.0f depth:1.0f];
    XCTAssertTrue([self.renderer setTextureStageColorOperation:TH08IOSRendererTextureOperationSelectArg1
                                               colorArgument1:TH08IOSRendererTextureArgumentFactor
                                               colorArgument2:TH08IOSRendererTextureArgumentDiffuse
                                                 alphaOperation:TH08IOSRendererTextureOperationSelectArg1
                                               alphaArgument1:TH08IOSRendererTextureArgumentFactor
                                               alphaArgument2:TH08IOSRendererTextureArgumentDiffuse]);
    [self.renderer setTextureFactorRed:64 green:128 blue:192 alpha:255];

    TH08IOSRendererVertex vertices[3] = {
        {-1.0f, -1.0f, 0.0f, 0.0f, 0.0f, 255, 255, 255, 255},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255, 255, 255, 255},
        { 0.0f,  1.0f, 0.0f, 0.5f, 1.0f, 255, 255, 255, 255}
    };
    XCTAssertTrue([self.renderer drawVertices:vertices count:3
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:0]);
    NSData *pixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(pixels);
    const uint8_t *bytes = (const uint8_t *)pixels.bytes;
    const NSUInteger center = (NSUInteger)(4u * 8u + 4u) * 4u;
    XCTAssertEqualWithAccuracy(bytes[center], 64, 3);
    XCTAssertEqualWithAccuracy(bytes[center + 1], 128, 3);
    XCTAssertEqualWithAccuracy(bytes[center + 2], 192, 3);
    XCTAssertEqualWithAccuracy(bytes[center + 3], 255, 3);

    XCTAssertFalse([self.renderer setTextureStageColorOperation:(TH08IOSRendererTextureOperation)99
                                                colorArgument1:TH08IOSRendererTextureArgumentTexture
                                                colorArgument2:TH08IOSRendererTextureArgumentDiffuse
                                                  alphaOperation:TH08IOSRendererTextureOperationModulate
                                                alphaArgument1:TH08IOSRendererTextureArgumentTexture
                                                alphaArgument2:TH08IOSRendererTextureArgumentDiffuse]);
    [self.renderer deleteTexture:target];
}

- (void)testLinearFogUsesPerVertexFogCoordinate
{
    const GLuint target = [self.renderer createRenderTargetWithWidth:8 height:8];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:8 height:8]);
    [self.renderer clearRed:0.0f green:0.0f blue:0.0f alpha:1.0f depth:1.0f];
    XCTAssertTrue([self.renderer setFogEnabled:YES colorRed:0.25f green:0.5f blue:0.75f start:0.0f end:0.5f]);
    XCTAssertFalse([self.renderer setFogEnabled:YES colorRed:0.0f green:0.0f blue:0.0f start:1.0f end:1.0f]);
    TH08IOSRendererVertex vertices[3] = {
        {-1.0f, -1.0f, 0.0f, 0.0f, 0.0f, 255, 255, 255, 255, 1.0f},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255, 255, 255, 255, 1.0f},
        { 0.0f,  1.0f, 0.0f, 0.5f, 1.0f, 255, 255, 255, 255, 1.0f}
    };
    XCTAssertTrue([self.renderer drawVertices:vertices count:3 primitive:TH08IOSRendererPrimitiveTriangles texture:0]);
    NSData *pixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(pixels);
    const uint8_t *bytes = (const uint8_t *)pixels.bytes;
    const NSUInteger center = (NSUInteger)(4u * 8u + 4u) * 4u;
    XCTAssertEqualWithAccuracy(bytes[center], 64, 4);
    XCTAssertEqualWithAccuracy(bytes[center + 1], 128, 4);
    XCTAssertEqualWithAccuracy(bytes[center + 2], 191, 4);
    XCTAssertEqual(bytes[center + 3], (uint8_t)255);
    [self.renderer deleteTexture:target];
}


@end
