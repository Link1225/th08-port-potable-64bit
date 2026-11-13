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

@end
