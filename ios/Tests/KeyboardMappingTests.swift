import Foundation

@main
enum KeyboardMappingTests {
    static func main() {
        let expected: [(UInt16, UInt8)] = [
            (0x1D, 0x5A), (0x1B, 0x58), (0x28, 0x0D), (0x29, 0x1B),
            (0x50, 0x25), (0x4F, 0x27), (0x52, 0x26), (0x51, 0x28),
            (0xE0, 0x11), (0xE4, 0x11), (0xE1, 0x10), (0xE5, 0x10),
            (0x13, 0x50), (0x07, 0x44), (0x14, 0x51), (0x16, 0x53),
            (0x15, 0x52), (0x4A, 0x24),
            (0x59, 0x61), (0x5A, 0x62), (0x5B, 0x63), (0x5C, 0x64),
            (0x5E, 0x66), (0x5F, 0x67), (0x60, 0x68), (0x61, 0x69)
        ]

        for (usage, virtualKey) in expected {
            precondition(
                TH08IOSKeyboardKeyMapping.virtualKeyCode(forHIDUsage: usage) == virtualKey,
                "Unexpected virtual-key mapping for HID usage 0x\(String(usage, radix: 16))"
            )
        }
        precondition(TH08IOSKeyboardKeyMapping.virtualKeyCode(forHIDUsage: 0x00) == nil)
        precondition(TH08IOSKeyboardKeyMapping.virtualKeyCode(forHIDUsage: 0xE2) == nil)

        let bothShiftKeys: Set<UInt16> = [0xE1, 0xE5]
        precondition(TH08IOSKeyboardKeyMapping.isVirtualKeyDown(0x10, forHIDUsages: bothShiftKeys))
        precondition(
            TH08IOSKeyboardKeyMapping.isVirtualKeyDown(0x10, forHIDUsages: [0xE5]),
            "Releasing one Shift key must not release the other"
        )
        precondition(
            !TH08IOSKeyboardKeyMapping.isVirtualKeyDown(0x10, forHIDUsages: []),
            "The virtual Shift key must be released when neither HID key is held"
        )

        print("iOS physical keyboard mapping tests passed (\(expected.count) mappings)")
    }
}
