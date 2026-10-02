import SwiftUI

struct QuickPanelView: View {
    let panel: PanelStore
    let capture: CaptureStore
    let browse: BrowseStore

    var body: some View {
        VStack(spacing: 0) {
            switch panel.screen {
            case .capture: CaptureView(store: capture)
            case .browse: BrowseView(store: browse)
            }
            Rectangle().fill(Theme.Colors.divider).frame(height: 1)
            footer
        }
        .background(GlassBackground())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(Theme.Colors.border))
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(Theme.Brand.mark, bundle: .main)
                .renderingMode(.template)
                .foregroundStyle(.secondary)
            Spacer()
            switch panel.screen {
            case .capture:
                hint("↩", "Save")
                hint("⌥O", "Notes")
                hint("⌘J", "Today")
            case .browse:
                hint("↩", "Copy")
                hint("⌘J", "Today")
            }
        }
        .font(Theme.Font.footer)
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.footerHeight)
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            KeyCap(label: keys)
            Text(label).foregroundStyle(.secondary)
        }
    }
}
