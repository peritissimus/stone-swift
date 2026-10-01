import StoneUI
import SwiftUI

@main
struct StoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // A template image, so it follows the menu bar's light or dark tint.
        MenuBarExtra("Stone", image: "StoneMark") {
            MenuBarMenu(container: delegate.container)
        }
    }
}

private struct MenuBarMenu: View {
    let container: AppContainer

    var body: some View {
        Button("Quick Note\(shortcutSuffix)") { container.shell?.showCapture() }
        Button("Search Notes") { container.shell?.showNotes() }
        Button("Today's Journal") { container.shell?.showToday() }
        Divider()
        Button("Open Workspace in Finder") { container.shell?.revealWorkspace() }
        Divider()
        Button("Quit Stone") { NSApp.terminate(nil) }
    }

    private var shortcutSuffix: String {
        if case .registered(let display) = container.hotKeyStatus { return "  \(display)" }
        return ""
    }
}
