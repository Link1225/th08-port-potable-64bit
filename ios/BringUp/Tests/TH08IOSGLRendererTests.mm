#import <XCTest/XCTest.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>

#import "../Renderer/TH08IOSGLRenderer.h"
#import "../Renderer/TH08IOSD3D8VertexLayout.h"
#import "../Renderer/TH08IOSD3D8StateMapping.h"
#import "../Renderer/TH08IOSD3D8Transform.h"

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



- (void)testDrawDisablesEveryVertexAttributeAfterSubmission
{
    const GLuint target = [self.renderer createRenderTargetWithWidth:8 height:8];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:8 height:8]);

    TH08IOSRendererVertex vertices[3] = {
        {-1.0f, -1.0f, 0.0f, 0.0f, 0.0f, 255, 255, 255, 255, 0.0f},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255, 255, 255, 255, 0.0f},
        { 0.0f,  1.0f, 0.0f, 0.5f, 1.0f, 255, 255, 255, 255, 0.0f}
    };
    XCTAssertTrue([self.renderer drawVertices:vertices count:3
                                    primitive:TH08IOSRendererPrimitiveTriangles
                                      texture:0]);

    for (GLuint index = 0; index < 4; ++index) {
        GLint enabled = GL_TRUE;
        glGetVertexAttribiv(index, GL_VERTEX_ATTRIB_ARRAY_ENABLED, &enabled);
        XCTAssertEqual(enabled, GL_FALSE, @"attribute %u leaked enabled state", index);
    }

    [self.renderer deleteTexture:target];
}

- (void)testD3D8FVFLayoutAndDecodeForXYZDiffuseAndUV
{
    using namespace TH08IOSD3D8;
    const uint32_t fvf = FVF_XYZ | FVF_DIFFUSE | (1u << FVF_TEXCOUNT_SHIFT);
    VertexLayout layout = {};
    XCTAssertEqual(static_cast<int>(BuildVertexLayout(fvf, &layout)),
                   static_cast<int>(LayoutError::None));
    XCTAssertEqual(layout.positionOffset, (size_t)0);
    XCTAssertEqual(layout.diffuseOffset, (size_t)12);
    XCTAssertEqual(layout.textureCoordinateOffset, (size_t)16);
    XCTAssertEqual(layout.textureCoordinate0Components, (uint8_t)2);
    XCTAssertEqual(layout.requiredStride, (size_t)24);

    uint8_t raw[24] = {};
    const float position[3] = {12.5f, -7.0f, 0.25f};
    const uint32_t diffuse = 0x80402010u;
    const float uv[2] = {0.25f, 0.75f};
    memcpy(raw, position, sizeof(position));
    memcpy(raw + 12, &diffuse, sizeof(diffuse));
    memcpy(raw + 16, uv, sizeof(uv));

    DecodedVertex decoded = {};
    XCTAssertEqual(static_cast<int>(DecodeVertex(layout, raw, sizeof(raw), &decoded)),
                   static_cast<int>(LayoutError::None));
    XCTAssertEqualWithAccuracy(decoded.x, 12.5f, 0.0001f);
    XCTAssertEqualWithAccuracy(decoded.y, -7.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(decoded.z, 0.25f, 0.0001f);
    XCTAssertEqual(decoded.rhw, 1.0f);
    XCTAssertEqual(decoded.red, (uint8_t)0x40);
    XCTAssertEqual(decoded.green, (uint8_t)0x20);
    XCTAssertEqual(decoded.blue, (uint8_t)0x10);
    XCTAssertEqual(decoded.alpha, (uint8_t)0x80);
    XCTAssertEqualWithAccuracy(decoded.u, 0.25f, 0.0001f);
    XCTAssertEqualWithAccuracy(decoded.v, 0.75f, 0.0001f);
}

- (void)testD3D8FVFLayoutSkipsOptionalFieldsAndAdditionalTextureSets
{
    using namespace TH08IOSD3D8;
    const uint32_t fvf = FVF_XYZRHW | FVF_NORMAL | FVF_PSIZE |
        FVF_DIFFUSE | FVF_SPECULAR | (2u << FVF_TEXCOUNT_SHIFT) |
        FVF_TEXCOORDSIZE1(0) | FVF_TEXCOORDSIZE3(1);
    VertexLayout layout = {};
    XCTAssertEqual(static_cast<int>(BuildVertexLayout(fvf, &layout)),
                   static_cast<int>(LayoutError::None));
    XCTAssertTrue(layout.transformed);
    XCTAssertEqual(layout.positionComponents, (uint8_t)4);
    XCTAssertEqual(layout.normalOffset, (size_t)16);
    XCTAssertEqual(layout.pointSizeOffset, (size_t)28);
    XCTAssertEqual(layout.diffuseOffset, (size_t)32);
    XCTAssertEqual(layout.specularOffset, (size_t)36);
    XCTAssertEqual(layout.textureCoordinateOffset, (size_t)40);
    XCTAssertEqual(layout.textureCoordinate0Components, (uint8_t)1);
    XCTAssertEqual(layout.requiredStride, (size_t)56);

    uint8_t raw[56] = {};
    const float position[4] = {640.0f, 480.0f, 0.5f, 2.0f};
    const uint32_t diffuse = 0xFFFFFFFFu;
    const float uv0 = 0.375f;
    memcpy(raw, position, sizeof(position));
    memcpy(raw + 32, &diffuse, sizeof(diffuse));
    memcpy(raw + 40, &uv0, sizeof(uv0));
    DecodedVertex decoded = {};
    XCTAssertEqual(static_cast<int>(DecodeVertex(layout, raw, sizeof(raw), &decoded)),
                   static_cast<int>(LayoutError::None));
    XCTAssertTrue(decoded.rhw == 2.0f);
    XCTAssertEqualWithAccuracy(decoded.u, 0.375f, 0.0001f);
    XCTAssertEqual(decoded.v, 0.0f);
}

- (void)testD3D8FVFRejectsUnsupportedPositionAndShortStride
{
    using namespace TH08IOSD3D8;
    VertexLayout layout = {};
    XCTAssertEqual(static_cast<int>(BuildVertexLayout(0x006u, &layout)),
                   static_cast<int>(LayoutError::UnsupportedPosition));
    XCTAssertEqual(static_cast<int>(BuildVertexLayout(FVF_XYZ | FVF_DIFFUSE, &layout)),
                   static_cast<int>(LayoutError::None));
    DecodedVertex decoded = {};
    uint8_t raw[15] = {};
    XCTAssertEqual(static_cast<int>(DecodeVertex(layout, raw, sizeof(raw), &decoded)),
                   static_cast<int>(LayoutError::StrideTooSmall));
    XCTAssertEqual(static_cast<int>(BuildVertexLayout(FVF_XYZ, NULL)),
                   static_cast<int>(LayoutError::NullOutput));
}

- (void)testD3D8StateMappingCoversSupportedTextureOperations
{
    using namespace TH08IOSD3D8;
    const uint32_t d3dOperations[] = {2u, 3u, 4u, 7u, 10u, 8u, 5u, 6u};
    const TextureOperation expected[] = {
        TextureSelectArg1, TextureSelectArg2, TextureModulate, TextureAdd,
        TextureSubtract, TextureAddSigned, TextureModulate2X, TextureModulate4X
    };
    for (NSUInteger index = 0; index < sizeof(d3dOperations) / sizeof(d3dOperations[0]); ++index) {
        TextureOperation actual = TextureSelectArg1;
        XCTAssertTrue(MapTextureOperation(d3dOperations[index], &actual));
        XCTAssertEqual(static_cast<int>(actual), static_cast<int>(expected[index]));
    }
    TextureOperation unsupported = TextureSelectArg1;
    XCTAssertFalse(MapTextureOperation(1u, &unsupported)); // D3DTOP_DISABLE is a separate stage state.
}

- (void)testD3D8StateMappingRejectsUnimplementedArgumentModifiers
{
    using namespace TH08IOSD3D8;
    TextureArgument argument = TextureArgumentTexture;
    XCTAssertTrue(MapTextureArgument(0u, &argument));
    XCTAssertEqual(static_cast<int>(argument), static_cast<int>(TextureArgumentDiffuse));
    XCTAssertTrue(MapTextureArgument(2u, &argument));
    XCTAssertEqual(static_cast<int>(argument), static_cast<int>(TextureArgumentTexture));
    XCTAssertTrue(MapTextureArgument(3u, &argument));
    XCTAssertEqual(static_cast<int>(argument), static_cast<int>(TextureArgumentFactor));
    XCTAssertFalse(MapTextureArgument(0x12u, &argument)); // D3DTA_COMPLEMENT
    XCTAssertFalse(MapTextureArgument(1u, &argument)); // D3DTA_CURRENT is not guessed as diffuse.
}

- (void)testD3D8StateMappingCoversCompareAndBlendFunctions
{
    using namespace TH08IOSD3D8;
    const GLenum compareExpected[] = {
        GL_NEVER, GL_LESS, GL_EQUAL, GL_LEQUAL,
        GL_GREATER, GL_NOTEQUAL, GL_GEQUAL, GL_ALWAYS
    };
    for (uint32_t d3d = 1u; d3d <= 8u; ++d3d) {
        GLenum actual = 0;
        XCTAssertTrue(MapCompareFunction(d3d, &actual));
        XCTAssertEqual(actual, compareExpected[d3d - 1u]);
    }
    const GLenum blendExpected[] = {
        GL_ZERO, GL_ONE, GL_SRC_COLOR, GL_ONE_MINUS_SRC_COLOR,
        GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_DST_ALPHA,
        GL_ONE_MINUS_DST_ALPHA, GL_DST_COLOR, GL_ONE_MINUS_DST_COLOR,
        GL_SRC_ALPHA_SATURATE
    };
    for (uint32_t d3d = 1u; d3d <= 11u; ++d3d) {
        GLenum actual = 0;
        XCTAssertTrue(MapBlendFactor(d3d, &actual));
        XCTAssertEqual(actual, blendExpected[d3d - 1u]);
    }
    GLenum unsupported = 0;
    XCTAssertFalse(MapCompareFunction(0u, &unsupported));
    XCTAssertFalse(MapBlendFactor(12u, &unsupported));
}

- (void)testD3D8XYZTransformMatchesLinuxAdapterViewportAndFogMath
{
    using namespace TH08IOSD3D8;
    Matrix4 identity = {};
    for (NSUInteger index = 0; index < 4; ++index)
        identity.m[index][index] = 1.0f;
    Viewport viewport = {10.0f, 20.0f, 640.0f, 480.0f, 0.0f, 1.0f};
    const float position[3] = {0.0f, 0.0f, 0.5f};
    HomogeneousPosition result = {};
    XCTAssertTrue(TransformXYZ(position, identity, identity, identity, viewport, &result));
    XCTAssertEqualWithAccuracy(result.x, 330.5f, 0.0001f);
    XCTAssertEqualWithAccuracy(result.y, 260.5f, 0.0001f);
    XCTAssertEqualWithAccuracy(result.z, 0.5f, 0.0001f);
    XCTAssertEqualWithAccuracy(result.w, 1.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(result.fogCoordinate, 0.5f, 0.0001f);
    XCTAssertFalse(TransformXYZ(position, identity, identity, identity,
                                 Viewport{0, 0, 0, 480, 0, 1}, &result));
}

- (void)testD3D8XYZRHWTransformHandlesReciprocalWAndZeroW
{
    using namespace TH08IOSD3D8;
    const float position[4] = {99.5f, 49.5f, 0.25f, 2.0f};
    HomogeneousPosition result = {};
    XCTAssertTrue(TransformXYZRHW(position, &result));
    XCTAssertEqualWithAccuracy(result.x, 50.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(result.y, 25.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(result.z, 0.125f, 0.0001f);
    XCTAssertEqualWithAccuracy(result.w, 0.5f, 0.0001f);
    XCTAssertEqual(result.fogCoordinate, 0.0f);

    const float zeroW[4] = {2.5f, 4.5f, 0.75f, 0.0f};
    XCTAssertTrue(TransformXYZRHW(zeroW, &result));
    XCTAssertEqualWithAccuracy(result.x, 3.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(result.y, 5.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(result.w, 1.0f, 0.0001f);
}

- (void)testD3D8TextureTransformUsesD3DMatrixConvention
{
    using namespace TH08IOSD3D8;
    Matrix4 texture = {};
    texture.m[0][0] = 2.0f;
    texture.m[1][0] = 3.0f;
    texture.m[2][0] = 5.0f;
    texture.m[0][1] = 7.0f;
    texture.m[1][1] = 11.0f;
    texture.m[2][1] = 13.0f;
    float u = 0.0f, v = 0.0f;
    TransformTextureCoordinate(0.25f, 0.5f, texture, &u, &v);
    XCTAssertEqualWithAccuracy(u, 7.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(v, 20.25f, 0.0001f);
}

- (void)testD3D8BlendOperationMappingRejectsUnsupportedMinMax
{
    using namespace TH08IOSD3D8;
    GLenum value = 0;
    XCTAssertTrue(MapBlendOperation(1u, &value));
    XCTAssertEqual(value, (GLenum)GL_FUNC_ADD);
    XCTAssertTrue(MapBlendOperation(2u, &value));
    XCTAssertEqual(value, (GLenum)GL_FUNC_SUBTRACT);
    XCTAssertTrue(MapBlendOperation(3u, &value));
    XCTAssertEqual(value, (GLenum)GL_FUNC_REVERSE_SUBTRACT);
    XCTAssertFalse(MapBlendOperation(4u, &value));
    XCTAssertFalse(MapBlendOperation(5u, &value));
    XCTAssertFalse(MapBlendOperation(1u, nullptr));
}

- (void)testD3D8TextureFilterMappingSupportsOnlyNonMipmapModes
{
    using namespace TH08IOSD3D8;
    GLenum value = 0;
    XCTAssertTrue(MapTextureFilter(1u, &value));
    XCTAssertEqual(value, (GLenum)GL_NEAREST);
    XCTAssertTrue(MapTextureFilter(2u, &value));
    XCTAssertEqual(value, (GLenum)GL_LINEAR);
    XCTAssertFalse(MapTextureFilter(0u, &value));
    XCTAssertFalse(MapTextureFilter(3u, &value));
    XCTAssertFalse(MapTextureFilter(1u, nullptr));
}

- (void)testD3D8TextureAddressMapping
{
    using namespace TH08IOSD3D8;
    GLenum value = 0;
    XCTAssertTrue(MapTextureAddress(1u, &value));
    XCTAssertEqual(value, (GLenum)GL_REPEAT);
    XCTAssertTrue(MapTextureAddress(2u, &value));
    XCTAssertEqual(value, (GLenum)GL_MIRRORED_REPEAT);
    XCTAssertTrue(MapTextureAddress(3u, &value));
    XCTAssertEqual(value, (GLenum)GL_CLAMP_TO_EDGE);
    XCTAssertFalse(MapTextureAddress(4u, &value));
    XCTAssertFalse(MapTextureAddress(5u, &value));
    XCTAssertFalse(MapTextureAddress(1u, nullptr));
}
@end
