import SwiftUI

/// A small keycap chip naming a shortcut beside the action it triggers.
struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 2)
            .background(Theme.Colors.keyCap, in: RoundedRectangle(cornerRadius: Theme.Radius.keyCap))
    }
}
