import Foundation

/// Maps USB HID keyboard usages to the Win32 virtual-key indices polled by
/// Controller::GetInput when the iOS UIKit keyboard bridge is active.
enum TH08IOSKeyboardKeyMapping {
    static func virtualKeyCode(forHIDUsage usage: UInt16) -> UInt8? {
        switch usage {
        case 0x1D: return 0x5A // Z -> VK_Z
        case 0x1B: return 0x58 // X -> VK_X
        case 0x28: return 0x0D // Return -> VK_RETURN
        case 0x29: return 0x1B // Escape -> VK_ESCAPE
        case 0x50: return 0x25 // Left -> VK_LEFT
        case 0x4F: return 0x27 // Right -> VK_RIGHT
        case 0x52: return 0x26 // Up -> VK_UP
        case 0x51: return 0x28 // Down -> VK_DOWN
        case 0xE0, 0xE4: return 0x11 // Left/right Control -> VK_CONTROL
        case 0xE1, 0xE5: return 0x10 // Left/right Shift -> VK_SHIFT
        case 0x13: return 0x50 // P -> VK_P
        case 0x07: return 0x44 // D -> VK_D
        case 0x14: return 0x51 // Q -> VK_Q
        case 0x16: return 0x53 // S -> VK_S
        case 0x15: return 0x52 // R -> VK_R
        case 0x4A: return 0x24 // Home -> VK_HOME
        case 0x59: return 0x61 // Keypad 1 -> VK_NUMPAD1
        case 0x5A: return 0x62 // Keypad 2 -> VK_NUMPAD2
        case 0x5B: return 0x63 // Keypad 3 -> VK_NUMPAD3
        case 0x5C: return 0x64 // Keypad 4 -> VK_NUMPAD4
        case 0x5E: return 0x66 // Keypad 6 -> VK_NUMPAD6
        case 0x5F: return 0x67 // Keypad 7 -> VK_NUMPAD7
        case 0x60: return 0x68 // Keypad 8 -> VK_NUMPAD8
        case 0x61: return 0x69 // Keypad 9 -> VK_NUMPAD9
        default: return nil
        }
    }
}
