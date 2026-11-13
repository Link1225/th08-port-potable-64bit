#import <Foundation/Foundation.h>
#include <stdint.h>
#include <stddef.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(uint32_t, TH08IOSD3D8PixelFormat) {
    TH08IOSD3D8PixelFormatR8G8B8 = 20,
    TH08IOSD3D8PixelFormatA8R8G8B8 = 21,
    TH08IOSD3D8PixelFormatX8R8G8B8 = 22,
    TH08IOSD3D8PixelFormatR5G6B5 = 23,
    TH08IOSD3D8PixelFormatX1R5G5B5 = 24,
    TH08IOSD3D8PixelFormatA1R5G5B5 = 25,
    TH08IOSD3D8PixelFormatA4R4G4B4 = 26,
    TH08IOSD3D8PixelFormatD16 = 80
};

enum {
    TH08IOSD3D8LockReadOnly = 0x00000010u,
    TH08IOSD3D8LockDiscard = 0x00002000u
};

typedef struct TH08IOSD3D8Rect {
    int32_t left;
    int32_t top;
    int32_t right;
    int32_t bottom;
} TH08IOSD3D8Rect;

typedef struct TH08IOSD3D8Point {
    int32_t x;
    int32_t y;
} TH08IOSD3D8Point;

typedef struct TH08IOSD3D8LockedRect {
    size_t pitch;
    void * _Nullable bits;
} TH08IOSD3D8LockedRect;

typedef struct TH08IOSD3D8SurfaceDescription {
    uint32_t width;
    uint32_t height;
    uint32_t format;
    size_t pitch;
    size_t byteSize;
} TH08IOSD3D8SurfaceDescription;

// CPU-backed D3D8-compatible surface storage. Coordinates are top-left based.
// Lock pitch always describes a complete row, even when a sub-rectangle is
// locked. RGBA readback is top-to-bottom and is available for color formats.
@interface TH08IOSD3D8Surface : NSObject

- (nullable instancetype)initWithWidth:(uint32_t)width
                                height:(uint32_t)height
                                format:(TH08IOSD3D8PixelFormat)format;

- (BOOL)getDescription:(TH08IOSD3D8SurfaceDescription *)description;
- (BOOL)lockRect:(nullable const TH08IOSD3D8Rect *)rect
           flags:(uint32_t)flags
      lockedRect:(TH08IOSD3D8LockedRect *)lockedRect;
- (BOOL)unlockRect;
- (BOOL)copyFromSurface:(TH08IOSD3D8Surface *)source
             sourceRect:(nullable const TH08IOSD3D8Rect *)sourceRect
        destinationPoint:(TH08IOSD3D8Point)destinationPoint;
- (nullable NSData *)copyRGBA8Pixels;

@property(nonatomic, readonly) uint32_t width;
@property(nonatomic, readonly) uint32_t height;
@property(nonatomic, readonly) TH08IOSD3D8PixelFormat format;
@property(nonatomic, readonly) uint64_t contentGeneration;
@property(nonatomic, readonly, getter=isLocked) BOOL locked;

@end

NS_ASSUME_NONNULL_END
