#import <XCTest/XCTest.h>
#import "../Renderer/TH08IOSD3D8StateMapping.h"

@interface TH08IOSD3D8TextureArgumentTests : XCTestCase
@end

@implementation TH08IOSD3D8TextureArgumentTests

- (void)testTextureArgumentSelectorsAndIndependentModifiers
{
    using namespace TH08IOSD3D8;
    TextureArgumentState state = {};

    XCTAssertTrue(MapTextureArgumentState(0x00u, &state));
    XCTAssertEqual(static_cast<int>(state.argument), static_cast<int>(TextureArgumentDiffuse));
    XCTAssertEqual(state.modifiers, (uint8_t)TextureArgumentModifierNone);

    XCTAssertTrue(MapTextureArgumentState(0x12u, &state));
    XCTAssertEqual(static_cast<int>(state.argument), static_cast<int>(TextureArgumentTexture));
    XCTAssertEqual(state.modifiers, (uint8_t)TextureArgumentModifierComplement);

    XCTAssertTrue(MapTextureArgumentState(0x23u, &state));
    XCTAssertEqual(static_cast<int>(state.argument), static_cast<int>(TextureArgumentFactor));
    XCTAssertEqual(state.modifiers, (uint8_t)TextureArgumentModifierAlphaReplicate);

    XCTAssertTrue(MapTextureArgumentState(0x32u, &state));
    XCTAssertEqual(static_cast<int>(state.argument), static_cast<int>(TextureArgumentTexture));
    XCTAssertEqual(state.modifiers,
                   (uint8_t)(TextureArgumentModifierComplement |
                             TextureArgumentModifierAlphaReplicate));
}

- (void)testTextureArgumentRejectsUnsupportedSelectorsAndReservedBits
{
    using namespace TH08IOSD3D8;
    TextureArgumentState state = {};
    XCTAssertFalse(MapTextureArgumentState(0x01u, &state)); // CURRENT
    XCTAssertFalse(MapTextureArgumentState(0x04u, &state)); // SPECULAR
    XCTAssertFalse(MapTextureArgumentState(0x44u, &state)); // reserved bit
    XCTAssertFalse(MapTextureArgumentState(0x00u, nullptr));
}

- (void)testLegacyArgumentMapperRemainsFailClosedForModifiers
{
    using namespace TH08IOSD3D8;
    TextureArgument argument = TextureArgumentTexture;
    XCTAssertTrue(MapTextureArgument(0x02u, &argument));
    XCTAssertEqual(static_cast<int>(argument), static_cast<int>(TextureArgumentTexture));
    XCTAssertFalse(MapTextureArgument(0x12u, &argument));
    XCTAssertFalse(MapTextureArgument(0x22u, &argument));
}

@end
