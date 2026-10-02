import SwiftUI

/// The first thing you see: one text area that saves to today's journal on ↩.
struct CaptureView: View {
    let store: CaptureStore

    var body: some View {
        ZStack(alignment: .topLeading) {
            CaptureTextEditor(store: store)
            if store.draft.isEmpty {
                Text("What's on your mind?")
                    .font(Theme.Font.capture)
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.sm)
    }
}
