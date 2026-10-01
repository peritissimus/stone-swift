import AppKit
import SwiftUI

/// Owns the panel's frame: placed on the pointer's screen at each show, resized per screen
/// with its top edge pinned so switching between capture and browse never jumps.
@MainActor
final class QuickPanelController: NSObject, NSWindowDelegate {
    private let panel: QuickPanel
    private let panelStore: PanelStore
    /// Whoever was frontmost when the panel opened, handed the keyboard back if Stone got activated.
    private var previousApp: NSRunningApplication?

    init(
        panelStore: PanelStore, capture: CaptureStore, browse: BrowseStore,
        onKey: @escaping (QuickPanel.KeyIntent) -> Bool
    ) {
        self.panelStore = panelStore
        let hosting = NSHostingView(rootView: QuickPanelView(panel: panelStore, capture: capture, browse: browse))
        // The controller owns the frame; SwiftUI must not resize the panel to its content.
        hosting.sizingOptions = []
        panel = QuickPanel(content: hosting)
        super.init()
        panel.delegate = self
        panel.onKey = onKey
    }

    var isVisible: Bool { panel.isVisible }

    /// Shows the current screen; when already visible, only resizes around the same top edge.
    func present() {
        let size = panelStore.screen == .capture ? Theme.Size.capture : Theme.Size.browse
        if panel.isVisible {
            let frame = panel.frame
            panel.setFrame(
                NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height),
                display: true)
        } else {
            let frontmost = NSWorkspace.shared.frontmostApplication
            previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
            if let visible = screenUnderPointer()?.visibleFrame {
                let top = visible.maxY - visible.height * Theme.Size.panelTopFraction
                panel.setFrame(
                    NSRect(x: visible.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height),
                    display: false)
            }
        }
        // Build the screen's views before ordering front, so there is a text view to focus.
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        focusInput()
        // An agent app that was never activated can drop its first key request, and a screen
        // switch mounts its field a pass later, so both are asserted again once things settle.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            if !self.panel.isKeyWindow { self.panel.makeKeyAndOrderFront(nil) }
            self.focusInput()
        }
    }

    /// Puts the caret where typing belongs: the note on capture, the search field on browse.
    private func focusInput() {
        switch panelStore.screen {
        case .capture:
            guard let editor = Self.first(CaptureTextView.self, in: panel.contentView) else { return }
            if panel.firstResponder !== editor {
                panel.makeFirstResponder(editor)
                editor.placeCaretAtEnd()
            }
        case .browse:
            guard let field = Self.first(NSTextField.self, in: panel.contentView, where: \.isEditable) else { return }
            // An editing field hands first responder to the window's shared field editor.
            let editing = (panel.firstResponder as? NSText)?.delegate === field
            if !editing { panel.makeFirstResponder(field) }
        }
    }

    private static func first<View: NSView>(
        _ type: View.Type, in root: NSView?, where accept: (View) -> Bool = { _ in true }
    ) -> View? {
        guard let root else { return nil }
        if let match = root as? View, accept(match) { return match }
        for child in root.subviews {
            if let match = first(type, in: child, where: accept) { return match }
        }
        return nil
    }

    /// A launch or Finder reopen activates Stone; only then does the keyboard need handing back.
    func hide() {
        panel.orderOut(nil)
        if NSApp.isActive { previousApp?.activate() }
        previousApp = nil
    }

    /// The draft is cleared or restored outside the undo system, so old typing must not be undoable.
    func resetUndo() {
        panel.undoManager?.removeAllActions()
    }

    /// ⇧↩ writes a real newline; AppKit's own Shift-Return inserts U+2028, which Markdown files dislike.
    func insertNewline() {
        (panel.firstResponder as? NSTextView)?.insertNewline(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
