import SwiftUI
import UIKit

struct KeyboardCaptureView: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardCaptureUIView {
        let view = KeyboardCaptureUIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        view.becomeFirstResponder()
        return view
    }

    func updateUIView(_ uiView: KeyboardCaptureUIView, context: Context) {
        if !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }
}

final class KeyboardCaptureUIView: UIView {
    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            becomeFirstResponder()
        } else {
            TH08IOSClearKeyboardState()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        update(presses, isDown: true)
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        update(presses, isDown: false)
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        update(presses, isDown: false)
        super.pressesCancelled(presses, with: event)
        TH08IOSClearKeyboardState()
    }

    private func update(_ presses: Set<UIPress>, isDown: Bool) {
        for press in presses {
            guard let key = press.key,
                  let scanCode = Self.directInputScanCode(for: key.keyCode) else {
                continue
            }
            TH08IOSSetKeyState(scanCode, isDown ? 1 : 0)
        }
    }

    // USB HID keyboard usages mapped to the DirectInput scan codes used by TH08.
    private static func directInputScanCode(for usage: UIKeyboardHIDUsage) -> UInt8? {
        switch usage.rawValue {
        case 0x1D: return 0x2C // Z
        case 0x1B: return 0x2D // X
        case 0x28: return 0x1C // Return
        case 0x29: return 0x01 // Escape
        case 0x50: return 0xCB // Left
        case 0x4F: return 0xCD // Right
        case 0x52: return 0xC8 // Up
        case 0x51: return 0xD0 // Down
        case 0xE0: return 0x1D // Left Control
        case 0xE1: return 0x2A // Left Shift
        default: return nil
        }
    }
}
