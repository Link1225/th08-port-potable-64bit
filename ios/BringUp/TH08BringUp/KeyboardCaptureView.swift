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
    private var pressedHIDUsages = Set<UInt16>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            becomeFirstResponder()
        } else {
            clearKeyboardState()
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
        super.pressesCancelled(presses, with: event)
        clearKeyboardState()
    }

    @objc private func applicationWillResignActive() {
        clearKeyboardState()
    }

    @objc private func applicationDidBecomeActive() {
        if window != nil {
            becomeFirstResponder()
        }
    }

    private func clearKeyboardState() {
        pressedHIDUsages.removeAll()
        TH08IOSClearKeyboardState()
    }

    private func update(_ presses: Set<UIPress>, isDown: Bool) {
        for press in presses {
            guard let key = press.key else {
                continue
            }
            let usage = UInt16(key.keyCode.rawValue)
            guard let virtualKeyCode = TH08IOSKeyboardKeyMapping.virtualKeyCode(
                forHIDUsage: usage
            ) else {
                continue
            }

            if isDown {
                pressedHIDUsages.insert(usage)
            } else {
                pressedHIDUsages.remove(usage)
            }

            let isVirtualKeyDown = TH08IOSKeyboardKeyMapping.isVirtualKeyDown(
                virtualKeyCode,
                forHIDUsages: pressedHIDUsages
            )
            TH08IOSSetKeyState(virtualKeyCode, isVirtualKeyDown ? 1 : 0)
        }
    }
}
