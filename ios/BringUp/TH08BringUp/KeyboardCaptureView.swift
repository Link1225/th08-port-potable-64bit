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
                  let virtualKeyCode = TH08IOSKeyboardKeyMapping.virtualKeyCode(
                    forHIDUsage: UInt16(key.keyCode.rawValue)
                  ) else {
                continue
            }
            TH08IOSSetKeyState(virtualKeyCode, isDown ? 1 : 0)
        }
    }
}
