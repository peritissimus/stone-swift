import AppKit
import SwiftUI

/// The frosted surface every Stone panel sits on.
struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var cornerRadius: CGFloat = Theme.Radius.panel

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
    }
}
