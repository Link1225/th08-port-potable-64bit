#import "TH08IOSRendererPreviewView.h"

@interface TH08IOSRendererPreviewView ()
@property (nonatomic, strong) TH08IOSGLRenderer *renderer;
@end

@implementation TH08IOSRendererPreviewView

- (instancetype)initWithFrame:(CGRect)frame
{
    EAGLContext *context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (context == nil)
        return nil;

    self = [super initWithFrame:frame context:context];
    if (self == nil)
        return nil;

    self.drawableColorFormat = GLKViewDrawableColorFormatRGBA8888;
    self.drawableDepthFormat = GLKViewDrawableDepthFormat16;
    self.delegate = self;
    self.enableSetNeedsDisplay = YES;
    self.opaque = YES;
    return self;
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    (void)view;
    (void)rect;
    if (![EAGLContext setCurrentContext:self.context])
        return;

    if (self.renderer == nil) {
        self.renderer = [[TH08IOSGLRenderer alloc] initWithCurrentContext];
        if (self.renderer == nil)
            return;
    }

    const GLsizei width = (GLsizei)self.drawableWidth;
    const GLsizei height = (GLsizei)self.drawableHeight;
    if (width <= 0 || height <= 0)
        return;

    if (![self.renderer setViewportX:0 y:0 width:width height:height])
        return;

    [self.renderer clearRed:0.035f green:0.045f blue:0.085f alpha:1.0f depth:1.0f];

    const TH08IOSRendererVertex vertices[3] = {
        {-0.78f, -0.62f, 0.0f, 0.0f, 0.0f,  70, 210, 255, 255, 0.0f},
        { 0.78f, -0.62f, 0.0f, 1.0f, 0.0f, 255, 105, 180, 255, 0.0f},
        { 0.00f,  0.78f, 0.0f, 0.5f, 1.0f, 255, 225, 105, 255, 0.0f}
    };

    [self.renderer drawVertices:vertices
                          count:3
                      primitive:TH08IOSRendererPrimitiveTriangles
                        texture:0];
}

@end
