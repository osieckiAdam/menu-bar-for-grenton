import AppKit
import SwiftUI

/// Reports when the window holding this view is shown and hidden.
///
/// `MenuBarExtra` keeps its window and its views alive between openings, so
/// `onAppear` is not a reliable "menu opened" signal; the window's occlusion
/// state is.
struct WindowVisibilityObserver: NSViewRepresentable {
    let onOpen: () -> Void
    let onClose: () -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = { visible in visible ? onOpen() : onClose() }
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onChange = { visible in visible ? onOpen() : onClose() }
    }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        private var isVisible = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Selector-based observers are removed automatically when the view goes away.
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            NotificationCenter.default.addObserver(
                self, selector: #selector(occlusionChanged),
                name: NSWindow.didChangeOcclusionStateNotification, object: window)
            update()
        }

        @objc private func occlusionChanged(_ notification: Notification) {
            update()
        }

        private func update() {
            let visible = window?.occlusionState.contains(.visible) ?? false
            guard visible != isVisible else { return }
            isVisible = visible
            onChange?(visible)
        }
    }
}
