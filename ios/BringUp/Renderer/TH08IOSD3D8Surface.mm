#import "TH08IOSD3D8Surface.h"

#include <algorithm>
#include <array>
#include <limits>
#include <new>
#include <stdexcept>
#include <vector>
#include <string.h>

namespace {

struct SurfaceStorage {
    std::vector<uint8_t> pixels;
    size_t pitch = 0;
    bool locked = false;
    bool readOnlyLock = false;
    uint64_t generation = 0;
};

size_t BytesPerPixel(TH08IOSD3D8PixelFormat format)
{
    switch (format) {
    case TH08IOSD3D8PixelFormatR8G8B8: return 3u;
    case TH08IOSD3D8PixelFormatR5G6B5:
    case TH08IOSD3D8PixelFormatX1R5G5B5:
    case TH08IOSD3D8PixelFormatA1R5G5B5:
    case TH08IOSD3D8PixelFormatA4R4G4B4:
    case TH08IOSD3D8PixelFormatD16: return 2u;
    case TH08IOSD3D8PixelFormatA8R8G8B8:
    case TH08IOSD3D8PixelFormatX8R8G8B8: return 4u;
    }
    return 0u;
}

uint8_t Expand5(uint32_t value)
{
    return static_cast<uint8_t>((value << 3u) | (value >> 2u));
}

uint8_t Expand6(uint32_t value)
{
    return static_cast<uint8_t>((value << 2u) | (value >> 4u));
}

bool DecodePixel(const uint8_t *source, TH08IOSD3D8PixelFormat format,
                 std::array<uint8_t, 4> *rgba)
{
    if (source == nullptr || rgba == nullptr) return false;
    uint16_t pixel = 0;
    switch (format) {
    case TH08IOSD3D8PixelFormatR8G8B8:
        (*rgba) = {{source[2], source[1], source[0], 255u}};
        return true;
    case TH08IOSD3D8PixelFormatA8R8G8B8:
        (*rgba) = {{source[2], source[1], source[0], source[3]}};
        return true;
    case TH08IOSD3D8PixelFormatX8R8G8B8:
        (*rgba) = {{source[2], source[1], source[0], 255u}};
        return true;
    case TH08IOSD3D8PixelFormatR5G6B5:
        memcpy(&pixel, source, sizeof(pixel));
        (*rgba) = {{Expand5((pixel >> 11u) & 31u),
                    Expand6((pixel >> 5u) & 63u),
                    Expand5(pixel & 31u), 255u}};
        return true;
    case TH08IOSD3D8PixelFormatX1R5G5B5:
    case TH08IOSD3D8PixelFormatA1R5G5B5:
        memcpy(&pixel, source, sizeof(pixel));
        (*rgba) = {{Expand5((pixel >> 10u) & 31u),
                    Expand5((pixel >> 5u) & 31u),
                    Expand5(pixel & 31u),
                    format == TH08IOSD3D8PixelFormatX1R5G5B5 ||
                        (pixel & 0x8000u) != 0u ? static_cast<uint8_t>(255u)
                                               : static_cast<uint8_t>(0u)}};
        return true;
    case TH08IOSD3D8PixelFormatA4R4G4B4:
        memcpy(&pixel, source, sizeof(pixel));
        (*rgba) = {{static_cast<uint8_t>(((pixel >> 8u) & 15u) * 17u),
                    static_cast<uint8_t>(((pixel >> 4u) & 15u) * 17u),
                    static_cast<uint8_t>((pixel & 15u) * 17u),
                    static_cast<uint8_t>(((pixel >> 12u) & 15u) * 17u)}};
        return true;
    case TH08IOSD3D8PixelFormatD16:
        return false;
    }
    return false;
}

bool EncodePixel(uint8_t *destination, TH08IOSD3D8PixelFormat format,
                 const std::array<uint8_t, 4> &rgba)
{
    if (destination == nullptr) return false;
    uint16_t pixel = 0;
    switch (format) {
    case TH08IOSD3D8PixelFormatR8G8B8:
        destination[0] = rgba[2]; destination[1] = rgba[1]; destination[2] = rgba[0];
        return true;
    case TH08IOSD3D8PixelFormatA8R8G8B8:
        destination[0] = rgba[2]; destination[1] = rgba[1];
        destination[2] = rgba[0]; destination[3] = rgba[3];
        return true;
    case TH08IOSD3D8PixelFormatX8R8G8B8:
        destination[0] = rgba[2]; destination[1] = rgba[1];
        destination[2] = rgba[0]; destination[3] = 255u;
        return true;
    case TH08IOSD3D8PixelFormatR5G6B5:
        pixel = static_cast<uint16_t>(((rgba[0] >> 3u) << 11u) |
                                      ((rgba[1] >> 2u) << 5u) |
                                      (rgba[2] >> 3u));
        memcpy(destination, &pixel, sizeof(pixel));
        return true;
    case TH08IOSD3D8PixelFormatX1R5G5B5:
    case TH08IOSD3D8PixelFormatA1R5G5B5:
        pixel = static_cast<uint16_t>(((format == TH08IOSD3D8PixelFormatX1R5G5B5 ||
                                        rgba[3] >= 128u) ? 0x8000u : 0u) |
                                      ((rgba[0] >> 3u) << 10u) |
                                      ((rgba[1] >> 3u) << 5u) |
                                      (rgba[2] >> 3u));
        memcpy(destination, &pixel, sizeof(pixel));
        return true;
    case TH08IOSD3D8PixelFormatA4R4G4B4:
        pixel = static_cast<uint16_t>(((rgba[3] >> 4u) << 12u) |
                                      ((rgba[0] >> 4u) << 8u) |
                                      ((rgba[1] >> 4u) << 4u) |
                                      (rgba[2] >> 4u));
        memcpy(destination, &pixel, sizeof(pixel));
        return true;
    case TH08IOSD3D8PixelFormatD16:
        return false;
    }
    return false;
}

bool ResolveRect(const TH08IOSD3D8Rect *requested, uint32_t width, uint32_t height,
                 TH08IOSD3D8Rect *resolved)
{
    if (resolved == nullptr) return false;
    TH08IOSD3D8Rect rect = requested == nullptr
        ? TH08IOSD3D8Rect{0, 0, static_cast<int32_t>(width), static_cast<int32_t>(height)}
        : *requested;
    if (rect.left < 0 || rect.top < 0 || rect.right <= rect.left ||
        rect.bottom <= rect.top ||
        static_cast<uint32_t>(rect.right) > width ||
        static_cast<uint32_t>(rect.bottom) > height)
        return false;
    *resolved = rect;
    return true;
}

} // namespace

@interface TH08IOSD3D8Surface () {
    SurfaceStorage *_storage;
    uint32_t _width;
    uint32_t _height;
    TH08IOSD3D8PixelFormat _format;
}
@end

@implementation TH08IOSD3D8Surface

- (nullable instancetype)initWithWidth:(uint32_t)width
                                height:(uint32_t)height
                                format:(TH08IOSD3D8PixelFormat)format
{
    self = [super init];
    if (self == nil) return nil;
    const size_t bytesPerPixel = BytesPerPixel(format);
    if (width == 0u || height == 0u || bytesPerPixel == 0u ||
        width > static_cast<uint32_t>(std::numeric_limits<int32_t>::max()) ||
        height > static_cast<uint32_t>(std::numeric_limits<int32_t>::max()) ||
        static_cast<size_t>(width) > std::numeric_limits<size_t>::max() / bytesPerPixel) {
        return nil;
    }
    const size_t pitch = static_cast<size_t>(width) * bytesPerPixel;
    if (static_cast<size_t>(height) > std::numeric_limits<size_t>::max() / pitch)
        return nil;

    SurfaceStorage *storage = new (std::nothrow) SurfaceStorage();
    if (storage == nullptr) return nil;
    try {
        storage->pixels.resize(pitch * static_cast<size_t>(height));
    } catch (const std::bad_alloc &) {
        delete storage;
        return nil;
    } catch (const std::length_error &) {
        delete storage;
        return nil;
    }
    storage->pitch = pitch;
    _storage = storage;
    _width = width;
    _height = height;
    _format = format;
    return self;
}

- (void)dealloc
{
    delete _storage;
    _storage = nullptr;
}

- (uint32_t)width { return _width; }
- (uint32_t)height { return _height; }
- (TH08IOSD3D8PixelFormat)format { return _format; }
- (uint64_t)contentGeneration { return _storage == nullptr ? 0u : _storage->generation; }
- (BOOL)isLocked { return _storage != nullptr && _storage->locked; }

- (BOOL)getDescription:(TH08IOSD3D8SurfaceDescription *)description
{
    if (description == nullptr || _storage == nullptr) return NO;
    description->width = _width;
    description->height = _height;
    description->format = static_cast<uint32_t>(_format);
    description->pitch = _storage->pitch;
    description->byteSize = _storage->pixels.size();
    return YES;
}

- (BOOL)lockRect:(const TH08IOSD3D8Rect *)rect
           flags:(uint32_t)flags
      lockedRect:(TH08IOSD3D8LockedRect *)lockedRect
{
    if (_storage == nullptr || lockedRect == nullptr || _storage->locked ||
        (flags & ~(TH08IOSD3D8LockReadOnly | TH08IOSD3D8LockDiscard)) != 0u ||
        ((flags & TH08IOSD3D8LockReadOnly) != 0u &&
         (flags & TH08IOSD3D8LockDiscard) != 0u))
        return NO;

    TH08IOSD3D8Rect region = {};
    if (!ResolveRect(rect, _width, _height, &region)) return NO;
    const bool discard = (flags & TH08IOSD3D8LockDiscard) != 0u;
    if (discard && (region.left != 0 || region.top != 0 ||
                    region.right != static_cast<int32_t>(_width) ||
                    region.bottom != static_cast<int32_t>(_height)))
        return NO;
    if (discard) std::fill(_storage->pixels.begin(), _storage->pixels.end(), 0u);

    const size_t bytesPerPixel = BytesPerPixel(_format);
    const size_t offset = static_cast<size_t>(region.top) * _storage->pitch +
                          static_cast<size_t>(region.left) * bytesPerPixel;
    _storage->locked = true;
    _storage->readOnlyLock = (flags & TH08IOSD3D8LockReadOnly) != 0u;
    lockedRect->pitch = _storage->pitch;
    lockedRect->bits = _storage->pixels.data() + offset;
    return YES;
}

- (BOOL)unlockRect
{
    if (_storage == nullptr || !_storage->locked) return NO;
    const bool modified = !_storage->readOnlyLock;
    _storage->locked = false;
    _storage->readOnlyLock = false;
    if (modified) {
        if (_storage->generation == std::numeric_limits<uint64_t>::max())
            _storage->generation = 1u;
        else
            ++_storage->generation;
    }
    return YES;
}

- (BOOL)copyFromSurface:(TH08IOSD3D8Surface *)source
             sourceRect:(const TH08IOSD3D8Rect *)sourceRect
        destinationPoint:(TH08IOSD3D8Point)destinationPoint
{
    if (source == nil || _storage == nullptr || source->_storage == nullptr ||
        _storage->locked || source->_storage->locked ||
        destinationPoint.x < 0 || destinationPoint.y < 0)
        return NO;

    TH08IOSD3D8Rect region = {};
    if (!ResolveRect(sourceRect, source->_width, source->_height, &region))
        return NO;
    const uint32_t copyWidth = static_cast<uint32_t>(region.right - region.left);
    const uint32_t copyHeight = static_cast<uint32_t>(region.bottom - region.top);
    if (static_cast<uint64_t>(destinationPoint.x) + copyWidth > _width ||
        static_cast<uint64_t>(destinationPoint.y) + copyHeight > _height)
        return NO;

    const bool sourceDepth = source->_format == TH08IOSD3D8PixelFormatD16;
    const bool destinationDepth = _format == TH08IOSD3D8PixelFormatD16;
    if (sourceDepth != destinationDepth) return NO;
    try {
        if (sourceDepth) {
            std::vector<uint8_t> temporary(static_cast<size_t>(copyWidth) * copyHeight * 2u);
            for (uint32_t y = 0; y < copyHeight; ++y) {
                const uint8_t *src = source->_storage->pixels.data() +
                    static_cast<size_t>(region.top + static_cast<int32_t>(y)) * source->_storage->pitch +
                    static_cast<size_t>(region.left) * 2u;
                memcpy(temporary.data() + static_cast<size_t>(y) * copyWidth * 2u,
                       src, static_cast<size_t>(copyWidth) * 2u);
            }
            for (uint32_t y = 0; y < copyHeight; ++y) {
                uint8_t *dst = _storage->pixels.data() +
                    static_cast<size_t>(destinationPoint.y + static_cast<int32_t>(y)) * _storage->pitch +
                    static_cast<size_t>(destinationPoint.x) * 2u;
                memcpy(dst, temporary.data() + static_cast<size_t>(y) * copyWidth * 2u,
                       static_cast<size_t>(copyWidth) * 2u);
            }
        } else {
            std::vector<std::array<uint8_t, 4>> temporary(
                static_cast<size_t>(copyWidth) * copyHeight);
            const size_t sourceBpp = BytesPerPixel(source->_format);
            const size_t destinationBpp = BytesPerPixel(_format);
            for (uint32_t y = 0; y < copyHeight; ++y) {
                for (uint32_t x = 0; x < copyWidth; ++x) {
                    const uint8_t *src = source->_storage->pixels.data() +
                        static_cast<size_t>(region.top + static_cast<int32_t>(y)) * source->_storage->pitch +
                        static_cast<size_t>(region.left + static_cast<int32_t>(x)) * sourceBpp;
                    if (!DecodePixel(src, source->_format,
                        &temporary[static_cast<size_t>(y) * copyWidth + x])) return NO;
                }
            }
            for (uint32_t y = 0; y < copyHeight; ++y) {
                for (uint32_t x = 0; x < copyWidth; ++x) {
                    uint8_t *dst = _storage->pixels.data() +
                        static_cast<size_t>(destinationPoint.y + static_cast<int32_t>(y)) * _storage->pitch +
                        static_cast<size_t>(destinationPoint.x + static_cast<int32_t>(x)) * destinationBpp;
                    if (!EncodePixel(dst, _format,
                        temporary[static_cast<size_t>(y) * copyWidth + x])) return NO;
                }
            }
        }
    } catch (const std::bad_alloc &) {
        return NO;
    } catch (const std::length_error &) {
        return NO;
    }

    if (_storage->generation == std::numeric_limits<uint64_t>::max())
        _storage->generation = 1u;
    else
        ++_storage->generation;
    return YES;
}

- (NSData *)copyRGBA8Pixels
{
    if (_storage == nullptr || _storage->locked ||
        _format == TH08IOSD3D8PixelFormatD16)
        return nil;
    if (static_cast<size_t>(_width) > std::numeric_limits<size_t>::max() / 4u ||
        static_cast<size_t>(_height) >
            std::numeric_limits<size_t>::max() / (static_cast<size_t>(_width) * 4u))
        return nil;
    const size_t outputSize = static_cast<size_t>(_width) * _height * 4u;
    std::vector<uint8_t> rgba;
    try {
        rgba.resize(outputSize);
    } catch (const std::bad_alloc &) {
        return nil;
    } catch (const std::length_error &) {
        return nil;
    }
    const size_t bytesPerPixel = BytesPerPixel(_format);
    for (uint32_t y = 0; y < _height; ++y) {
        for (uint32_t x = 0; x < _width; ++x) {
            const uint8_t *source = _storage->pixels.data() +
                static_cast<size_t>(y) * _storage->pitch +
                static_cast<size_t>(x) * bytesPerPixel;
            std::array<uint8_t, 4> pixel = {};
            if (!DecodePixel(source, _format, &pixel)) return nil;
            memcpy(rgba.data() + (static_cast<size_t>(y) * _width + x) * 4u,
                   pixel.data(), 4u);
        }
    }
    return [NSData dataWithBytes:rgba.data() length:rgba.size()];
}

@end
