import AppKit
import SwiftUI

/// Hosts `CaptureTextView` and keeps it and `CaptureStore.draft` in step.
struct CaptureTextEditor: NSViewRepresentable {
    let store: CaptureStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CaptureTextView(frame: .zero)
        textView.configureForCapture()
        textView.string = store.draft
        textView.delegate = context.coordinator
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        return scroll
    }

    /// The store changes the draft itself on submit (cleared) and on a failed save (restored).
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? CaptureTextView,
            textView.string != store.draft, !textView.hasMarkedText()
        else { return }
        textView.string = store.draft
        textView.placeCaretAtEnd()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let store: CaptureStore

        init(store: CaptureStore) {
            self.store = store
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            store.draft = textView.string
        }
    }
}
