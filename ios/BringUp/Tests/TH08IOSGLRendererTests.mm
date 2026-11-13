#import <XCTest/XCTest.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>

#include <limits>
#include <vector>
#include <string.h>

#import "../Renderer/TH08IOSGLRenderer.h"
#import "../Renderer/TH08IOSD3D8DeviceAdapter.h"
#import "../Renderer/TH08IOSD3D8VertexLayout.h"
#import "../Renderer/TH08IOSD3D8StateMapping.h"
#import "../Renderer/TH08IOSD3D8Transform.h"
#import "../Renderer/TH08IOSD3D8VertexConversion.h"
#import "../Renderer/TH08IOSD3D8Surface.h"

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

- (void)testD3D8ClearSeparatesColorAndDepthFlags
{
    const GLuint target = [self.renderer createRenderTargetWithWidth:8 height:8];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:8 height:8]);

    TH08IOSD3D8DeviceAdapter *adapter =
        [[TH08IOSD3D8DeviceAdapter alloc] initWithRenderer:self.renderer];
    XCTAssertNotNil(adapter);
    XCTAssertTrue([adapter clearColorEnabled:YES color:0xFF000000u
                               depthEnabled:YES depth:1.0f]);
    XCTAssertTrue([self.renderer setDepthCompareFunction:GL_LESS]);
    [self.renderer setDepthTestingEnabled:YES writeEnabled:YES];

    TH08IOSRendererVertex nearTriangle[3] = {
        {-1.0f, -1.0f, -0.5f, 0.0f, 0.0f, 255, 0, 0, 255},
        { 1.0f, -1.0f, -0.5f, 1.0f, 0.0f, 255, 0, 0, 255},
        { 0.0f,  1.0f, -0.5f, 0.5f, 1.0f, 255, 0, 0, 255}
    };
    XCTAssertTrue([self.renderer drawVertices:nearTriangle count:3
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:0]);

    // Color-only clear must leave the near triangle's depth value intact.
    XCTAssertTrue([adapter clearColorEnabled:YES color:0xFF0000FFu
                               depthEnabled:NO depth:1.0f]);
    TH08IOSRendererVertex farTriangle[3] = {
        {-1.0f, -1.0f, 0.5f, 0.0f, 0.0f, 0, 255, 0, 255},
        { 1.0f, -1.0f, 0.5f, 1.0f, 0.0f, 0, 255, 0, 255},
        { 0.0f,  1.0f, 0.5f, 0.5f, 1.0f, 0, 255, 0, 255}
    };
    XCTAssertTrue([self.renderer drawVertices:farTriangle count:3
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:0]);
    NSData *colorCleared = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(colorCleared);
    const uint8_t *colorBytes = (const uint8_t *)colorCleared.bytes;
    const NSUInteger center = (NSUInteger)(4u * 8u + 4u) * 4u;
    XCTAssertEqual(colorBytes[center], (uint8_t)0);
    XCTAssertEqual(colorBytes[center + 1], (uint8_t)0);
    XCTAssertEqual(colorBytes[center + 2], (uint8_t)255);

    // Depth-only clear permits the farther triangle without changing the blue color first.
    XCTAssertTrue([adapter clearColorEnabled:NO color:0u
                               depthEnabled:YES depth:1.0f]);
    XCTAssertTrue([self.renderer drawVertices:farTriangle count:3
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:0]);
    NSData *depthCleared = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(depthCleared);
    const uint8_t *depthBytes = (const uint8_t *)depthCleared.bytes;
    XCTAssertLessThan(depthBytes[center], (uint8_t)10);
    XCTAssertGreaterThan(depthBytes[center + 1], (uint8_t)240);
    XCTAssertLessThan(depthBytes[center + 2], (uint8_t)10);

    [self.renderer setDepthTestingEnabled:NO writeEnabled:YES];
    [self.renderer setDepthCompareFunction:GL_ALWAYS];
    [self.renderer clearRed:0.0f green:0.0f blue:0.0f alpha:1.0f depth:1.0f];
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

    for (GLuint index = 0; index < 5; ++index) {
        GLint enabled = GL_TRUE;
        glGetVertexAttribiv(index, GL_VERTEX_ATTRIB_ARRAY_ENABLED, &enabled);
        XCTAssertEqual(enabled, GL_FALSE, @"attribute %u leaked enabled state", index);
    }

    [self.renderer deleteTexture:target];
}

- (void)testSpecularVertexColorAddsToDiffuseInShader
{
    const GLuint target = [self.renderer createRenderTargetWithWidth:8 height:8];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:8 height:8]);
    [self.renderer clearRed:0.0f green:0.0f blue:0.0f alpha:1.0f depth:1.0f];

    TH08IOSRendererVertex vertices[3] = {
        {-1.0f, -1.0f, 0.0f, 0.0f, 0.0f, 255, 0, 0, 255, 0.0f, 0, 255, 0, 255},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255, 0, 0, 255, 0.0f, 0, 255, 0, 255},
        { 0.0f,  1.0f, 0.0f, 0.5f, 1.0f, 255, 0, 0, 255, 0.0f, 0, 255, 0, 255}
    };
    XCTAssertTrue([self.renderer drawVertices:vertices count:3
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:0]);

    NSData *pixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(pixels);
    const uint8_t *bytes = (const uint8_t *)pixels.bytes;
    const NSUInteger center = (NSUInteger)(4u * 8u + 4u) * 4u;
    XCTAssertGreaterThan(bytes[center], (uint8_t)200);
    XCTAssertGreaterThan(bytes[center + 1], (uint8_t)200);
    XCTAssertLessThan(bytes[center + 2], (uint8_t)20);
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
    const uint32_t specular = 0xA1B2C3D4u;
    memcpy(raw + 36, &specular, sizeof(specular));
    memcpy(raw + 40, &uv0, sizeof(uv0));
    DecodedVertex decoded = {};
    XCTAssertEqual(static_cast<int>(DecodeVertex(layout, raw, sizeof(raw), &decoded)),
                   static_cast<int>(LayoutError::None));
    XCTAssertTrue(decoded.rhw == 2.0f);
    XCTAssertEqual(decoded.specularRed, (uint8_t)0xB2);
    XCTAssertEqual(decoded.specularGreen, (uint8_t)0xC3);
    XCTAssertEqual(decoded.specularBlue, (uint8_t)0xD4);
    XCTAssertEqual(decoded.specularAlpha, (uint8_t)0xA1);
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

    const float negativeW[4] = {2.5f, 4.5f, 0.75f, -1.0f};
    XCTAssertFalse(TransformXYZRHW(negativeW, &result));
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


- (void)testD3D8FVFBatchFlowsThroughTheES2DrawAdapter
{
    struct D3D8Vertex {
        float x;
        float y;
        float z;
        uint32_t diffuse;
    };
    const D3D8Vertex vertices[3] = {
        {-1.0f, -1.0f, 0.0f, 0xFFFF0000u},
        { 1.0f, -1.0f, 0.0f, 0xFFFF0000u},
        { 0.0f,  1.0f, 0.0f, 0xFFFF0000u}
    };

    TH08IOSD3D8::Matrix4 identity = {};
    for (size_t index = 0; index < 4; ++index)
        identity.m[index][index] = 1.0f;
    const TH08IOSD3D8::Viewport viewport = {0.0f, 0.0f, 8.0f, 8.0f, 0.0f, 1.0f};

    const GLuint target = [self.renderer createRenderTargetWithWidth:8 height:8];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:8 height:8]);
    [self.renderer clearRed:0.0f green:0.0f blue:0.0f alpha:1.0f depth:1.0f];

    TH08IOSD3D8DeviceAdapter *adapter =
        [[TH08IOSD3D8DeviceAdapter alloc] initWithRenderer:self.renderer];
    XCTAssertNotNil(adapter);
    XCTAssertTrue([adapter setWorldTransform:identity]);
    XCTAssertTrue([adapter setViewTransform:identity]);
    XCTAssertTrue([adapter setProjectionTransform:identity]);
    XCTAssertTrue([adapter setTextureTransform:identity]);
    XCTAssertTrue([adapter setD3DViewport:viewport]);
    GLint actualViewport[4] = {-1, -1, -1, -1};
    glGetIntegerv(GL_VIEWPORT, actualViewport);
    XCTAssertEqual(actualViewport[0], 0);
    XCTAssertEqual(actualViewport[1], 0);
    XCTAssertEqual(actualViewport[2], 8);
    XCTAssertEqual(actualViewport[3], 8);

    TH08IOSD3D8::Matrix4 invalidTransform = identity;
    invalidTransform.m[0][0] = NAN;
    XCTAssertFalse([adapter setWorldTransform:invalidTransform]);
    TH08IOSD3D8::Viewport invalidViewport = viewport;
    invalidViewport.width = 0.0f;
    XCTAssertFalse([adapter setD3DViewport:invalidViewport]);

    XCTAssertTrue([adapter drawCurrentFVFVertices:vertices
                                              fvf:TH08IOSD3D8::FVF_XYZ | TH08IOSD3D8::FVF_DIFFUSE
                                            stride:sizeof(D3D8Vertex)
                                             count:3
                                         primitive:TH08IOSRendererPrimitiveTriangles]);

    NSData *pixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(pixels);
    const uint8_t *bytes = (const uint8_t *)pixels.bytes;
    const NSUInteger center = (NSUInteger)(4u * 8u + 4u) * 4u;
    XCTAssertGreaterThan(bytes[center], (uint8_t)200);
    XCTAssertLessThan(bytes[center + 1], (uint8_t)20);
    XCTAssertLessThan(bytes[center + 2], (uint8_t)20);

    struct D3D8TransformedVertex {
        float x;
        float y;
        float z;
        float rhw;
        uint32_t diffuse;
    };
    const D3D8TransformedVertex transformedVertices[3] = {
        {0.0f, 8.0f, 0.5f, 0.5f, 0xFFFF0000u},
        {8.0f, 8.0f, 0.5f, 0.5f, 0xFFFF0000u},
        {4.0f, 0.0f, 0.5f, 0.5f, 0xFFFF0000u}
    };
    [self.renderer clearRed:0.0f green:0.0f blue:0.0f alpha:1.0f depth:1.0f];
    XCTAssertTrue([adapter drawCurrentFVFVertices:transformedVertices
                                                  fvf:TH08IOSD3D8::FVF_XYZRHW | TH08IOSD3D8::FVF_DIFFUSE
                                                stride:sizeof(D3D8TransformedVertex)
                                                 count:3
                                             primitive:TH08IOSRendererPrimitiveTriangles]);
    pixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(pixels);
    bytes = (const uint8_t *)pixels.bytes;
    XCTAssertGreaterThan(bytes[center], (uint8_t)200);
    XCTAssertLessThan(bytes[center + 1], (uint8_t)20);
    XCTAssertLessThan(bytes[center + 2], (uint8_t)20);

    XCTAssertTrue([self.renderer bindRenderTargetTexture:0]);
    [self.renderer deleteTexture:target];
}

- (void)testD3D8XYZTransformRejectsNonFiniteAndDegenerateInputs
{
    using namespace TH08IOSD3D8;
    Matrix4 identity = {};
    for (size_t index = 0; index < 4; ++index)
        identity.m[index][index] = 1.0f;
    const float position[3] = {0.25f, -0.5f, 0.75f};
    const Viewport viewport = {0.0f, 0.0f, 320.0f, 240.0f, 0.0f, 1.0f};

    HomogeneousPosition output = {11.0f, 12.0f, 13.0f, 14.0f, 15.0f};
    XCTAssertTrue(TransformXYZ(position, identity, identity, identity, viewport, &output));
    const HomogeneousPosition validOutput = output;

    const float invalidPosition[3] = {NAN, 0.0f, 0.0f};
    XCTAssertFalse(TransformXYZ(invalidPosition, identity, identity, identity, viewport, &output));
    XCTAssertEqual(output.x, validOutput.x);
    XCTAssertEqual(output.y, validOutput.y);
    XCTAssertEqual(output.z, validOutput.z);
    XCTAssertEqual(output.w, validOutput.w);
    XCTAssertEqual(output.fogCoordinate, validOutput.fogCoordinate);

    Matrix4 invalidMatrix = identity;
    invalidMatrix.m[1][2] = INFINITY;
    XCTAssertFalse(TransformXYZ(position, identity, invalidMatrix, identity, viewport, &output));
    XCTAssertEqual(output.x, validOutput.x);

    Matrix4 zeroWProjection = identity;
    zeroWProjection.m[3][3] = 0.0f;
    XCTAssertFalse(TransformXYZ(position, identity, identity, zeroWProjection, viewport, &output));
    XCTAssertEqual(output.x, validOutput.x);

    Viewport invalidViewport = viewport;
    invalidViewport.maxZ = invalidViewport.minZ;
    XCTAssertFalse(TransformXYZ(position, identity, identity, identity, invalidViewport, &output));
    XCTAssertEqual(output.x, validOutput.x);

    Matrix4 overflowingWorld = identity;
    overflowingWorld.m[0][0] = std::numeric_limits<float>::max();
    const float largePosition[3] = {std::numeric_limits<float>::max(), 0.0f, 0.0f};
    XCTAssertFalse(TransformXYZ(largePosition, overflowingWorld, identity, identity,
                                viewport, &output));
    XCTAssertEqual(output.x, validOutput.x);
}

- (void)testD3D8TransformedVerticesPreserveLegacyZeroRHWAndRejectInvalidRHW
{
    using namespace TH08IOSD3D8;
    const float valid[4] = {12.0f, 24.0f, 0.5f, 0.5f};
    HomogeneousPosition output = {};
    XCTAssertTrue(TransformXYZRHW(valid, &output));
    XCTAssertEqualWithAccuracy(output.x, 25.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(output.y, 49.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(output.z, 1.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(output.w, 2.0f, 0.0001f);

    // The legacy D3D8 compatibility path treats zero RHW as unit reciprocal W.
    const float zeroRHW[4] = {12.0f, 24.0f, 0.5f, 0.0f};
    XCTAssertTrue(TransformXYZRHW(zeroRHW, &output));
    XCTAssertEqualWithAccuracy(output.x, 12.5f, 0.0001f);
    XCTAssertEqualWithAccuracy(output.y, 24.5f, 0.0001f);
    XCTAssertEqualWithAccuracy(output.z, 0.5f, 0.0001f);
    XCTAssertEqualWithAccuracy(output.w, 1.0f, 0.0001f);

    const HomogeneousPosition unchanged = output;
    const float invalidRHW[4] = {12.0f, 24.0f, 0.5f, NAN};
    XCTAssertFalse(TransformXYZRHW(invalidRHW, &output));
    XCTAssertEqual(output.x, unchanged.x);
    XCTAssertEqual(output.y, unchanged.y);
    XCTAssertEqual(output.z, unchanged.z);
    XCTAssertEqual(output.w, unchanged.w);

    const float negativeRHW[4] = {12.0f, 24.0f, 0.5f, -1.0f};
    XCTAssertFalse(TransformXYZRHW(negativeRHW, &output));
    XCTAssertEqual(output.x, unchanged.x);
    XCTAssertEqual(output.y, unchanged.y);
    XCTAssertEqual(output.z, unchanged.z);
    XCTAssertEqual(output.w, unchanged.w);
}

- (void)testD3D8ViewportCoordinatesConvertBackToES2ClipSpace
{
    using namespace TH08IOSD3D8;
    const Viewport viewport = {10.0f, 20.0f, 200.0f, 100.0f, 0.2f, 0.8f};
    const float ndc[4] = {0.25f, -0.5f, 0.4f, 2.0f};
    HomogeneousPosition screen = {};
    screen.x = (viewport.x + 0.5f) * ndc[3] +
               (ndc[0] + ndc[3]) * viewport.width * 0.5f;
    screen.y = (viewport.y + 0.5f) * ndc[3] +
               (ndc[3] - ndc[1]) * viewport.height * 0.5f;
    screen.z = viewport.minZ * ndc[3] +
               ((ndc[2] / ndc[3] + 1.0f) * 0.5f) *
               (viewport.maxZ - viewport.minZ) * ndc[3];
    screen.w = ndc[3];

    float clip[4] = {};
    XCTAssertTrue(ViewportToClipPosition(screen, viewport, clip));
    for (size_t index = 0; index < 4; ++index)
        XCTAssertEqualWithAccuracy(clip[index], ndc[index], 0.0001f);

    Viewport invalid = viewport;
    invalid.height = 0.0f;
    const float unchanged[4] = {9.0f, 8.0f, 7.0f, 6.0f};
    float output[4] = {9.0f, 8.0f, 7.0f, 6.0f};
    XCTAssertFalse(ViewportToClipPosition(screen, invalid, output));
    for (size_t index = 0; index < 4; ++index)
        XCTAssertEqual(output[index], unchanged[index]);

    HomogeneousPosition zeroW = screen;
    zeroW.w = 0.0f;
    XCTAssertFalse(ViewportToClipPosition(zeroW, viewport, output));
    for (size_t index = 0; index < 4; ++index)
        XCTAssertEqual(output[index], unchanged[index]);
}

- (void)testD3D8VertexConversionCombinesFVFTransformColorAndTextureCoordinates
{
    using namespace TH08IOSD3D8;
    const uint32_t fvf = FVF_XYZ | FVF_DIFFUSE | (1u << FVF_TEXCOUNT_SHIFT);
    VertexLayout layout = {};
    XCTAssertEqual(BuildVertexLayout(fvf, &layout), LayoutError::None);

    std::vector<uint8_t> bytes(layout.requiredStride, 0);
    const float xyz[3] = {0.25f, -0.5f, 0.75f};
    const uint32_t color = 0x80402010u;
    const float uv[2] = {0.2f, 0.4f};
    memcpy(bytes.data(), xyz, sizeof(xyz));
    memcpy(bytes.data() + layout.diffuseOffset, &color, sizeof(color));
    memcpy(bytes.data() + layout.textureCoordinateOffset, uv, sizeof(uv));

    Matrix4 identity = {};
    for (NSUInteger index = 0; index < 4; ++index)
        identity.m[index][index] = 1.0f;
    Viewport viewport = {0, 0, 320, 240, 0, 1};
    ConvertedVertex output = {};
    XCTAssertEqual(ConvertVertex(layout, bytes.data(), bytes.size(), identity, identity,
                                 identity, identity, viewport, &output), LayoutError::None);
    XCTAssertEqualWithAccuracy(output.x, 160.5f + 0.25f * 160.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(output.y, 120.5f + 0.5f * 120.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(output.z, 0.75f, 0.0001f);
    XCTAssertEqualWithAccuracy(output.w, 1.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(output.u, 0.2f, 0.0001f);
    XCTAssertEqualWithAccuracy(output.v, 0.4f, 0.0001f);
    XCTAssertEqual(output.specularRed, (uint8_t)0);
    XCTAssertEqual(output.red, (uint8_t)0x40);
    XCTAssertEqual(output.green, (uint8_t)0x20);
    XCTAssertEqual(output.blue, (uint8_t)0x10);
    XCTAssertEqual(output.alpha, (uint8_t)0x80);
    XCTAssertEqualWithAccuracy(output.fogCoordinate, 0.75f, 0.0001f);
}


- (void)testD3D8BatchVertexConversionIsTransactional
{
    using namespace TH08IOSD3D8;
    VertexLayout layout = {};
    XCTAssertEqual(BuildVertexLayout(FVF_XYZ | FVF_DIFFUSE, &layout), LayoutError::None);

    struct SourceVertex { float x, y, z; uint32_t color; };
    const SourceVertex source[2] = {
        {0.0f, 0.0f, 0.0f, 0xFFFFFFFFu},
        {1.0f, 0.0f, 0.0f, 0xFF00FF00u}
    };
    Matrix4 identity = {};
    for (size_t i = 0; i < 4; ++i) identity.m[i][i] = 1.0f;
    Viewport viewport = {0.0f, 0.0f, 100.0f, 100.0f, 0.0f, 1.0f};
    std::vector<ConvertedVertex> output(1);
    XCTAssertEqual(ConvertVertices(layout, source, sizeof(SourceVertex), 2,
        identity, identity, identity, identity, viewport, &output),
        BatchConversionError::None);
    XCTAssertEqual(output.size(), (size_t)2);
    XCTAssertEqualWithAccuracy(output[1].x, 100.5f, 0.001f);

    const size_t previousSize = output.size();
    XCTAssertEqual(ConvertVertices(layout, source, sizeof(SourceVertex) - 1, 2,
        identity, identity, identity, identity, viewport, &output),
        BatchConversionError::VertexDecodeFailed);
    XCTAssertEqual(output.size(), previousSize);

    const size_t overflowingStride = std::numeric_limits<size_t>::max() / 2u + 1u;
    XCTAssertEqual(ConvertVertices(layout, source, overflowingStride, 3,
        identity, identity, identity, identity, viewport, &output),
        BatchConversionError::CountOverflow);
    XCTAssertEqual(output.size(), previousSize);
}
- (void)testD3D8VertexConversionDoesNotModifyOutputOnDecodeFailure
{
    using namespace TH08IOSD3D8;
    VertexLayout layout = {};
    XCTAssertEqual(BuildVertexLayout(FVF_XYZ, &layout), LayoutError::None);
    Matrix4 identity = {};
    for (NSUInteger index = 0; index < 4; ++index)
        identity.m[index][index] = 1.0f;
    Viewport viewport = {0, 0, 100, 100, 0, 1};
    ConvertedVertex output = {};
    output.x = 123.0f;
    uint8_t shortVertex[4] = {};
    XCTAssertEqual(ConvertVertex(layout, shortVertex, sizeof(shortVertex), identity,
                                 identity, identity, identity, viewport, &output),
                   LayoutError::StrideTooSmall);
    XCTAssertEqualWithAccuracy(output.x, 123.0f, 0.0001f);
}
- (void)testTextureArgumentComplementAndAlphaReplicateAffectRenderedPixels
{
    const GLuint target = [self.renderer createRenderTargetWithWidth:8 height:8];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:8 height:8]);

    const uint8_t texel[4] = {51, 102, 153, 64};
    const GLuint texture = [self.renderer createTextureWithRGBA8Pixels:texel
                                                                 width:1
                                                                height:1
                                                              rowBytes:4];
    XCTAssertNotEqual(texture, 0u);
    XCTAssertTrue([self.renderer setTextureStageColorOperation:
                   TH08IOSRendererTextureOperationSelectArg1
                   colorArgument1:TH08IOSRendererTextureArgumentTexture
                   colorArgument2:TH08IOSRendererTextureArgumentDiffuse
                   alphaOperation:TH08IOSRendererTextureOperationSelectArg1
                   alphaArgument1:TH08IOSRendererTextureArgumentTexture
                   alphaArgument2:TH08IOSRendererTextureArgumentDiffuse]);

    TH08IOSRendererVertex vertices[3] = {
        {-1.0f, -1.0f, 0.0f, 0.5f, 0.5f, 255, 255, 255, 255},
        { 1.0f, -1.0f, 0.0f, 0.5f, 0.5f, 255, 255, 255, 255},
        { 0.0f,  1.0f, 0.0f, 0.5f, 0.5f, 255, 255, 255, 255}
    };

    [self.renderer clearRed:0 green:0 blue:0 alpha:1 depth:1];
    XCTAssertTrue([self.renderer setTextureStageArgumentModifiersColor1:1 color2:0 alpha1:0 alpha2:0]);
    XCTAssertTrue([self.renderer drawVertices:vertices count:3
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:texture]);
    NSData *complementPixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(complementPixels);
    const uint8_t *complement = (const uint8_t *)complementPixels.bytes;
    const NSUInteger center = (NSUInteger)(4u * 8u + 4u) * 4u;
    XCTAssertGreaterThan(complement[center], (uint8_t)185);
    XCTAssertGreaterThan(complement[center + 1], (uint8_t)135);
    XCTAssertGreaterThan(complement[center + 2], (uint8_t)85);
    XCTAssertGreaterThan(complement[center + 3], (uint8_t)45);
    XCTAssertLessThan(complement[center + 3], (uint8_t)85);

    [self.renderer clearRed:0 green:0 blue:0 alpha:1 depth:1];
    XCTAssertTrue([self.renderer setTextureStageArgumentModifiersColor1:2 color2:0 alpha1:0 alpha2:0]);
    XCTAssertTrue([self.renderer drawVertices:vertices count:3
                                      primitive:TH08IOSRendererPrimitiveTriangles texture:texture]);
    NSData *replicatedPixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(replicatedPixels);
    const uint8_t *replicated = (const uint8_t *)replicatedPixels.bytes;
    XCTAssertGreaterThan(replicated[center], (uint8_t)45);
    XCTAssertLessThan(replicated[center], (uint8_t)85);
    XCTAssertEqualWithAccuracy(replicated[center], replicated[center + 1], 2);
    XCTAssertEqualWithAccuracy(replicated[center], replicated[center + 2], 2);
    XCTAssertGreaterThan(replicated[center + 3], (uint8_t)45);
    XCTAssertLessThan(replicated[center + 3], (uint8_t)85);

    XCTAssertFalse([self.renderer setTextureStageArgumentModifiersColor1:4 color2:0 alpha1:0 alpha2:0]);
    [self.renderer deleteTexture:texture];
    [self.renderer deleteTexture:target];
}


- (void)testD3D8StateMappingIdentifiesSupportedDeviceStateSlots
{
    using namespace TH08IOSD3D8;
    const uint32_t renderStateValues[] = {
        7u, 14u, 15u, 19u, 20u, 23u, 24u, 25u, 27u, 28u,
        34u, 36u, 37u, 60u, 140u, 168u, 171u
    };
    const RenderState renderExpected[] = {
        RenderState::ZEnable, RenderState::ZWriteEnable, RenderState::AlphaTestEnable,
        RenderState::SourceBlend, RenderState::DestinationBlend, RenderState::ZFunction,
        RenderState::AlphaReference, RenderState::AlphaFunction, RenderState::AlphaBlendEnable,
        RenderState::FogEnable, RenderState::FogColor, RenderState::FogStart, RenderState::FogEnd,
        RenderState::TextureFactor, RenderState::FogVertexMode, RenderState::ColorWriteEnable,
        RenderState::BlendOperation
    };
    for (NSUInteger i = 0; i < sizeof(renderStateValues) / sizeof(renderStateValues[0]); ++i) {
        RenderState actual = RenderState::ZEnable;
        XCTAssertTrue(MapRenderState(renderStateValues[i], &actual));
        XCTAssertEqual(static_cast<int>(actual), static_cast<int>(renderExpected[i]));
    }
    RenderState untouched = RenderState::FogEnable;
    XCTAssertFalse(MapRenderState(255u, &untouched));
    XCTAssertEqual(static_cast<int>(untouched), static_cast<int>(RenderState::FogEnable));
    XCTAssertFalse(MapRenderState(7u, NULL));

    const uint32_t textureStateValues[] = {1u, 2u, 3u, 4u, 5u, 6u, 13u, 14u, 16u, 17u};
    const TextureStageState textureExpected[] = {
        TextureStageState::ColorOperation, TextureStageState::ColorArgument1,
        TextureStageState::ColorArgument2, TextureStageState::AlphaOperation,
        TextureStageState::AlphaArgument1, TextureStageState::AlphaArgument2,
        TextureStageState::AddressU, TextureStageState::AddressV,
        TextureStageState::MagnificationFilter, TextureStageState::MinificationFilter
    };
    for (NSUInteger i = 0; i < sizeof(textureStateValues) / sizeof(textureStateValues[0]); ++i) {
        TextureStageState actual = TextureStageState::ColorOperation;
        XCTAssertTrue(MapTextureStageState(textureStateValues[i], &actual));
        XCTAssertEqual(static_cast<int>(actual), static_cast<int>(textureExpected[i]));
    }
    TextureStageState textureUntouched = TextureStageState::AddressU;
    XCTAssertFalse(MapTextureStageState(31u, &textureUntouched));
    XCTAssertEqual(static_cast<int>(textureUntouched), static_cast<int>(TextureStageState::AddressU));
    XCTAssertFalse(MapTextureStageState(1u, NULL));
}



- (void)testD3D8DeviceAdapterAppliesSupportedStateAndRejectsUnsupportedValues
{
    TH08IOSD3D8DeviceAdapter *adapter = [[TH08IOSD3D8DeviceAdapter alloc] initWithRenderer:self.renderer];
    XCTAssertNotNil(adapter);
    XCTAssertTrue([adapter setRenderState:27u value:1u]);
    XCTAssertTrue([adapter setRenderState:19u value:5u]);
    XCTAssertTrue([adapter setRenderState:20u value:6u]);
    XCTAssertTrue([adapter setRenderState:171u value:2u]);
    XCTAssertTrue([adapter setRenderState:168u value:7u]);
    XCTAssertTrue([adapter setTextureStageState:0u state:1u value:4u]);
    XCTAssertTrue([adapter setTextureStageState:0u state:2u value:0x12u]);
    XCTAssertTrue([adapter setTextureStageState:0u state:17u value:1u]);
    XCTAssertFalse([adapter setRenderState:999u value:1u]);
    XCTAssertFalse([adapter setRenderState:7u value:2u]);
    XCTAssertFalse([adapter setTextureStageState:1u state:1u value:4u]);
    XCTAssertFalse([adapter setTextureStageState:0u state:17u value:3u]);
}



- (void)testD3D8DeviceAdapterDrawsOnlyWithOwnedTextures
{
    TH08IOSD3D8DeviceAdapter *adapter = [[TH08IOSD3D8DeviceAdapter alloc] initWithRenderer:self.renderer];
    XCTAssertNotNil(adapter);
    const uint8_t pixel[4] = {0u, 255u, 0u, 255u};
    const GLuint texture = [adapter createTextureWithRGBA8Pixels:pixel width:1 height:1 rowBytes:4];
    XCTAssertNotEqual(texture, 0u);
    const GLuint target = [self.renderer createRenderTargetWithWidth:8 height:8];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:8 height:8]);
    [self.renderer clearRed:0 green:0 blue:0 alpha:1 depth:1];

    TH08IOSRendererVertex vertices[3] = {
        {-1, -1, 0, 0, 0, 255, 255, 255, 255},
        { 1, -1, 0, 1, 0, 255, 255, 255, 255},
        { 0,  1, 0, 0.5f, 1, 255, 255, 255, 255}
    };
    XCTAssertFalse([adapter setTexture:texture + 1u]);
    XCTAssertTrue([adapter setTexture:texture]);
    XCTAssertTrue([adapter drawBoundVertices:vertices count:3
                                    primitive:TH08IOSRendererPrimitiveTriangles]);
    NSData *pixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:8 height:8];
    XCTAssertNotNil(pixels);
    const uint8_t *bytes = (const uint8_t *)pixels.bytes;
    const NSUInteger center = (NSUInteger)(4u * 8u + 4u) * 4u;
    XCTAssertLessThan(bytes[center], (uint8_t)20);
    XCTAssertGreaterThan(bytes[center + 1], (uint8_t)200);
    XCTAssertLessThan(bytes[center + 2], (uint8_t)20);

    [self.renderer deleteTexture:target];
    XCTAssertTrue([adapter deleteTexture:texture]);
    // Releasing the bound texture automatically returns the stage to untextured.
    XCTAssertTrue([adapter drawBoundVertices:vertices count:3
                                    primitive:TH08IOSRendererPrimitiveTriangles]);
    XCTAssertFalse([adapter setTexture:texture]);
}


- (void)testD3D8DeviceAdapterOwnsTextureResources
{
    TH08IOSD3D8DeviceAdapter *adapter = [[TH08IOSD3D8DeviceAdapter alloc] initWithRenderer:self.renderer];
    XCTAssertNotNil(adapter);
    const uint8_t pixel[4] = {255u, 255u, 255u, 255u};
    const GLuint texture = [adapter createTextureWithRGBA8Pixels:pixel width:1 height:1 rowBytes:4];
    XCTAssertNotEqual(texture, 0u);
    XCTAssertFalse([adapter deleteTexture:0u]);
    XCTAssertFalse([adapter deleteTexture:texture + 1u]);
    EAGLContext *otherContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    XCTAssertNotNil(otherContext);
    XCTAssertTrue([EAGLContext setCurrentContext:otherContext]);
    XCTAssertFalse([adapter deleteTexture:texture]);
    XCTAssertTrue([EAGLContext setCurrentContext:self.context]);
    XCTAssertTrue([adapter deleteTexture:texture]);
    XCTAssertFalse([adapter deleteTexture:texture]);
}


- (void)testD3D8SurfaceUploadsToRendererTexture
{
    TH08IOSD3D8Surface *surface = [[TH08IOSD3D8Surface alloc]
        initWithWidth:1 height:1 format:TH08IOSD3D8PixelFormatA8R8G8B8];
    XCTAssertNotNil(surface);
    TH08IOSD3D8LockedRect locked = {};
    XCTAssertTrue([surface lockRect:nullptr flags:0u lockedRect:&locked]);
    const uint8_t pixel[4] = {30u, 20u, 10u, 255u};
    memcpy(locked.bits, pixel, sizeof(pixel));
    XCTAssertTrue([surface unlockRect]);

    TH08IOSD3D8DeviceAdapter *adapter =
        [[TH08IOSD3D8DeviceAdapter alloc] initWithRenderer:self.renderer];
    XCTAssertNotNil(adapter);
    const GLuint texture = [adapter createTextureFromSurface:surface];
    XCTAssertNotEqual(texture, 0u);

    const GLuint target = [self.renderer createRenderTargetWithWidth:4 height:4];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:4 height:4]);
    [self.renderer clearRed:0.0f green:0.0f blue:0.0f alpha:1.0f depth:1.0f];

    TH08IOSRendererVertex vertices[6] = {
        {-1.0f, -1.0f, 0.0f, 0.0f, 0.0f, 255u, 255u, 255u, 255u},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255u, 255u, 255u, 255u},
        {-1.0f,  1.0f, 0.0f, 0.0f, 1.0f, 255u, 255u, 255u, 255u},
        {-1.0f,  1.0f, 0.0f, 0.0f, 1.0f, 255u, 255u, 255u, 255u},
        { 1.0f, -1.0f, 0.0f, 1.0f, 0.0f, 255u, 255u, 255u, 255u},
        { 1.0f,  1.0f, 0.0f, 1.0f, 1.0f, 255u, 255u, 255u, 255u}
    };
    XCTAssertTrue([adapter drawVertices:vertices count:6
                               primitive:TH08IOSRendererPrimitiveTriangles texture:texture]);
    NSData *pixels = [self.renderer copyCurrentFramebufferRGBA8PixelsWithWidth:4 height:4];
    XCTAssertNotNil(pixels);
    const uint8_t *bytes = static_cast<const uint8_t *>(pixels.bytes);
    const size_t center = (size_t)(2u * 4u + 2u) * 4u;
    XCTAssertEqualWithAccuracy(bytes[center], 10u, 2u);
    XCTAssertEqualWithAccuracy(bytes[center + 1u], 20u, 2u);
    XCTAssertEqualWithAccuracy(bytes[center + 2u], 30u, 2u);
    XCTAssertEqual(bytes[center + 3u], 255u);

    XCTAssertTrue([surface lockRect:nullptr flags:TH08IOSD3D8LockReadOnly
                         lockedRect:&locked]);
    XCTAssertEqual([adapter createTextureFromSurface:surface], 0u);
    XCTAssertTrue([surface unlockRect]);

    XCTAssertTrue([adapter deleteTexture:texture]);
    [self.renderer deleteTexture:target];
}

- (void)testD3D8SurfaceAcceptsBottomUpRGBAReadback
{
    TH08IOSD3D8Surface *surface = [[TH08IOSD3D8Surface alloc]
        initWithWidth:1 height:2 format:TH08IOSD3D8PixelFormatA8R8G8B8];
    XCTAssertNotNil(surface);
    const uint8_t bottomUp[8] = {
        0u, 0u, 255u, 255u,  // bottom row: blue
        255u, 0u, 0u, 255u   // top row: red
    };
    XCTAssertTrue([surface replaceWithRGBA8Pixels:bottomUp rowBytes:4u bottomUp:YES]);
    NSData *rgba = [surface copyRGBA8Pixels];
    XCTAssertNotNil(rgba);
    const uint8_t *bytes = static_cast<const uint8_t *>(rgba.bytes);
    XCTAssertEqual(bytes[0], 255u);
    XCTAssertEqual(bytes[1], 0u);
    XCTAssertEqual(bytes[2], 0u);
    XCTAssertEqual(bytes[4], 0u);
    XCTAssertEqual(bytes[5], 0u);
    XCTAssertEqual(bytes[6], 255u);
}

- (void)testD3D8AdapterCopiesFramebufferIntoSurface
{
    TH08IOSD3D8Surface *surface = [[TH08IOSD3D8Surface alloc]
        initWithWidth:4 height:4 format:TH08IOSD3D8PixelFormatR5G6B5];
    XCTAssertNotNil(surface);
    TH08IOSD3D8DeviceAdapter *adapter =
        [[TH08IOSD3D8DeviceAdapter alloc] initWithRenderer:self.renderer];
    XCTAssertNotNil(adapter);

    const GLuint target = [self.renderer createRenderTargetWithWidth:4 height:4];
    XCTAssertNotEqual(target, 0u);
    XCTAssertTrue([self.renderer bindRenderTargetTexture:target]);
    XCTAssertTrue([self.renderer setViewportX:0 y:0 width:4 height:4]);
    [self.renderer clearRed:0.25f green:0.5f blue:0.75f alpha:1.0f depth:1.0f];
    XCTAssertTrue([adapter copyCurrentFramebufferToSurface:surface]);
    NSData *rgba = [surface copyRGBA8Pixels];
    XCTAssertNotNil(rgba);
    const uint8_t *bytes = static_cast<const uint8_t *>(rgba.bytes);
    XCTAssertEqualWithAccuracy(bytes[0], 66u, 8u);
    XCTAssertEqualWithAccuracy(bytes[1], 130u, 8u);
    XCTAssertEqualWithAccuracy(bytes[2], 189u, 8u);

    TH08IOSD3D8LockedRect locked = {};
    XCTAssertTrue([surface lockRect:nullptr flags:TH08IOSD3D8LockReadOnly
                         lockedRect:&locked]);
    XCTAssertFalse([adapter copyCurrentFramebufferToSurface:surface]);
    XCTAssertTrue([surface unlockRect]);

    XCTAssertTrue([self.renderer bindRenderTargetTexture:0]);
    [self.renderer deleteTexture:target];
}

- (void)testD3D8CopyRectsCopiesOnlyRequestedRegion
{
    TH08IOSD3D8Surface *source = [[TH08IOSD3D8Surface alloc]
        initWithWidth:2 height:2 format:TH08IOSD3D8PixelFormatA8R8G8B8];
    TH08IOSD3D8Surface *destination = [[TH08IOSD3D8Surface alloc]
        initWithWidth:3 height:3 format:TH08IOSD3D8PixelFormatA8R8G8B8];
    XCTAssertNotNil(source);
    XCTAssertNotNil(destination);

    TH08IOSD3D8LockedRect locked = {};
    XCTAssertTrue([source lockRect:nullptr flags:0u lockedRect:&locked]);
    // A8R8G8B8 surface storage is byte-ordered B, G, R, A.
    const uint8_t sourcePixels[16] = {
        0u, 0u, 255u, 255u, 0u, 255u, 0u, 255u,
        255u, 0u, 0u, 255u, 0u, 255u, 255u, 255u
    };
    memcpy(locked.bits, sourcePixels, sizeof(sourcePixels));
    XCTAssertTrue([source unlockRect]);

    XCTAssertTrue([destination lockRect:nullptr flags:0u lockedRect:&locked]);
    memset(locked.bits, 0, 3u * locked.pitch);
    XCTAssertTrue([destination unlockRect]);

    TH08IOSD3D8DeviceAdapter *adapter =
        [[TH08IOSD3D8DeviceAdapter alloc] initWithRenderer:self.renderer];
    XCTAssertNotNil(adapter);
    const TH08IOSD3D8Rect rect = {1, 0, 2, 2};
    XCTAssertTrue([adapter copySurface:source sourceRect:rect toSurface:destination
                          destinationX:2 destinationY:1]);

    NSData *pixels = [destination copyRGBA8Pixels];
    XCTAssertNotNil(pixels);
    const uint8_t *bytes = static_cast<const uint8_t *>(pixels.bytes);
    const size_t copiedTop = (1u * 3u + 2u) * 4u;
    const size_t copiedBottom = (2u * 3u + 2u) * 4u;
    XCTAssertEqual(bytes[copiedTop], 0u);
    XCTAssertEqual(bytes[copiedTop + 1u], 255u);
    XCTAssertEqual(bytes[copiedTop + 2u], 0u);
    XCTAssertEqual(bytes[copiedBottom], 255u);
    XCTAssertEqual(bytes[copiedBottom + 1u], 255u);
    XCTAssertEqual(bytes[copiedBottom + 2u], 0u);
    XCTAssertEqual(bytes[0], 0u);
    XCTAssertEqual(bytes[1], 0u);
    XCTAssertFalse([adapter copySurface:source sourceRect:rect toSurface:destination
                           destinationX:3 destinationY:1]);
}

- (void)testD3D8SurfaceDescriptionAndSubrectangleLockPitch
{
    TH08IOSD3D8Surface *surface = [[TH08IOSD3D8Surface alloc]
        initWithWidth:4 height:3 format:TH08IOSD3D8PixelFormatA8R8G8B8];
    XCTAssertNotNil(surface);
    TH08IOSD3D8SurfaceDescription description = {};
    XCTAssertTrue([surface getDescription:&description]);
    XCTAssertEqual(description.width, 4u);
    XCTAssertEqual(description.height, 3u);
    XCTAssertEqual(description.pitch, (size_t)16u);
    XCTAssertEqual(description.byteSize, (size_t)48u);

    const TH08IOSD3D8Rect rect = {1, 1, 3, 2};
    TH08IOSD3D8LockedRect locked = {};
    XCTAssertTrue([surface lockRect:&rect flags:0u lockedRect:&locked]);
    XCTAssertEqual(locked.pitch, (size_t)16u);
    XCTAssertNotEqual(locked.bits, nullptr);
    uint8_t *pixel = static_cast<uint8_t *>(locked.bits);
    pixel[0] = 30u; pixel[1] = 20u; pixel[2] = 10u; pixel[3] = 40u;
    XCTAssertTrue(surface.isLocked);
    XCTAssertTrue([surface unlockRect]);
    XCTAssertFalse(surface.isLocked);
    XCTAssertEqual(surface.contentGeneration, 1u);

    NSData *rgba = [surface copyRGBA8Pixels];
    XCTAssertNotNil(rgba);
    const uint8_t *bytes = static_cast<const uint8_t *>(rgba.bytes);
    const size_t offset = (size_t)(1u * 4u + 1u) * 4u;
    XCTAssertEqual(bytes[offset], 10u);
    XCTAssertEqual(bytes[offset + 1u], 20u);
    XCTAssertEqual(bytes[offset + 2u], 30u);
    XCTAssertEqual(bytes[offset + 3u], 40u);
}

- (void)testD3D8SurfaceRejectsInvalidLocksAndTracksReadOnly
{
    TH08IOSD3D8Surface *surface = [[TH08IOSD3D8Surface alloc]
        initWithWidth:2 height:2 format:TH08IOSD3D8PixelFormatX8R8G8B8];
    XCTAssertNotNil(surface);
    TH08IOSD3D8LockedRect locked = {};
    const TH08IOSD3D8Rect outside = {-1, 0, 1, 1};
    XCTAssertFalse([surface lockRect:&outside flags:0u lockedRect:&locked]);
    const TH08IOSD3D8Rect partial = {0, 0, 1, 1};
    XCTAssertFalse([surface lockRect:&partial flags:TH08IOSD3D8LockDiscard
                          lockedRect:&locked]);
    XCTAssertFalse([surface lockRect:nullptr flags:0x80000000u lockedRect:&locked]);
    XCTAssertTrue([surface lockRect:nullptr flags:TH08IOSD3D8LockReadOnly
                         lockedRect:&locked]);
    XCTAssertFalse([surface lockRect:nullptr flags:0u lockedRect:&locked]);
    XCTAssertNil([surface copyRGBA8Pixels]);
    XCTAssertTrue([surface unlockRect]);
    XCTAssertEqual(surface.contentGeneration, 0u);
    XCTAssertFalse([surface unlockRect]);

    XCTAssertTrue([surface lockRect:nullptr flags:TH08IOSD3D8LockDiscard
                         lockedRect:&locked]);
    memset(locked.bits, 0x7F, locked.pitch * 2u);
    XCTAssertTrue([surface unlockRect]);
    XCTAssertEqual(surface.contentGeneration, 1u);
}

- (void)testD3D8SurfaceCopiesAndConvertsPixelFormats
{
    TH08IOSD3D8Surface *source = [[TH08IOSD3D8Surface alloc]
        initWithWidth:1 height:1 format:TH08IOSD3D8PixelFormatA8R8G8B8];
    TH08IOSD3D8Surface *destination = [[TH08IOSD3D8Surface alloc]
        initWithWidth:1 height:1 format:TH08IOSD3D8PixelFormatA4R4G4B4];
    XCTAssertNotNil(source);
    XCTAssertNotNil(destination);

    TH08IOSD3D8LockedRect locked = {};
    XCTAssertTrue([source lockRect:nullptr flags:0u lockedRect:&locked]);
    uint8_t *sourcePixel = static_cast<uint8_t *>(locked.bits);
    sourcePixel[0] = 30u; sourcePixel[1] = 20u;
    sourcePixel[2] = 10u; sourcePixel[3] = 40u;
    XCTAssertTrue([source unlockRect]);

    const TH08IOSD3D8Point origin = {0, 0};
    XCTAssertTrue([destination copyFromSurface:source sourceRect:nullptr
                               destinationPoint:origin]);
    NSData *rgba = [destination copyRGBA8Pixels];
    XCTAssertNotNil(rgba);
    const uint8_t *bytes = static_cast<const uint8_t *>(rgba.bytes);
    XCTAssertEqual(bytes[0], 0u);
    XCTAssertEqual(bytes[1], 17u);
    XCTAssertEqual(bytes[2], 17u);
    XCTAssertEqual(bytes[3], 34u);

    TH08IOSD3D8Surface *depth = [[TH08IOSD3D8Surface alloc]
        initWithWidth:1 height:1 format:TH08IOSD3D8PixelFormatD16];
    XCTAssertNotNil(depth);
    XCTAssertNil([depth copyRGBA8Pixels]);
    XCTAssertFalse([destination copyFromSurface:depth sourceRect:nullptr
                                destinationPoint:origin]);
}

- (void)testD3D8SurfaceCopyHandlesOverlapAndBounds
{
    TH08IOSD3D8Surface *surface = [[TH08IOSD3D8Surface alloc]
        initWithWidth:3 height:1 format:TH08IOSD3D8PixelFormatA8R8G8B8];
    XCTAssertNotNil(surface);
    TH08IOSD3D8LockedRect locked = {};
    XCTAssertTrue([surface lockRect:nullptr flags:0u lockedRect:&locked]);
    uint8_t *pixels = static_cast<uint8_t *>(locked.bits);
    const uint8_t values[12] = {
        0u, 0u, 10u, 255u,
        0u, 0u, 20u, 255u,
        0u, 0u, 30u, 255u
    };
    memcpy(pixels, values, sizeof(values));
    XCTAssertTrue([surface unlockRect]);

    const TH08IOSD3D8Rect firstTwo = {0, 0, 2, 1};
    const TH08IOSD3D8Point shiftRight = {1, 0};
    XCTAssertTrue([surface copyFromSurface:surface sourceRect:&firstTwo
                           destinationPoint:shiftRight]);
    NSData *rgba = [surface copyRGBA8Pixels];
    XCTAssertNotNil(rgba);
    const uint8_t *bytes = static_cast<const uint8_t *>(rgba.bytes);
    XCTAssertEqual(bytes[0], 10u);
    XCTAssertEqual(bytes[4], 10u);
    XCTAssertEqual(bytes[8], 20u);

    const TH08IOSD3D8Point invalidDestination = {2, 0};
    XCTAssertFalse([surface copyFromSurface:surface sourceRect:&firstTwo
                            destinationPoint:invalidDestination]);
}


@end
