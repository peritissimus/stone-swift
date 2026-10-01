import AppKit
import SwiftUI

/// A transient pill that reports an outcome without taking focus.
@MainActor
final class HUDController {
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    func show(_ message: String, symbol: String = "checkmark.circle.fill", isError: Bool = false) {
        dismissal?.cancel()
        panel?.orderOut(nil)
        let content = HUDView(message: message, symbol: isError ? "exclamationmark.triangle.fill" : symbol, isError: isError)
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        let hud = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hud.level = .statusBar
        hud.isOpaque = false
        hud.backgroundColor = .clear
        hud.hasShadow = true
        hud.ignoresMouseEvents = true
        hud.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hud.contentView = hosting
        if let visible = screenUnderPointer()?.visibleFrame {
            hud.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + visible.height * 0.18))
        }
        hud.orderFrontRegardless()
        panel = hud
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: Theme.Motion.hudVisible)
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.panel = nil
        }
    }
}

private struct HUDView: View {
    let message: String
    let symbol: String
    let isError: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: symbol).foregroundStyle(isError ? Color.orange : Color.green)
            Text(message).font(.system(size: 13, weight: .medium)).lineLimit(2)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .frame(maxWidth: 420)
        .background(GlassBackground(cornerRadius: Theme.Radius.hud))
    }
}
