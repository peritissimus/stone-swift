import AppKit
import StoneDomain

/// The driving adapter's entry point: one panel that opens on capture, plus the routes to
/// look back through notes. It takes notes; it never edits one.
@MainActor
public final class StoneShell {
    public enum HotKeyStatus: Equatable {
        case registered(String)
        /// Stone's config sets no quick-capture shortcut.
        case disabled
        case invalid(String)
        /// Another app — often Stone desktop — already owns the chord.
        case unavailable(String)
    }

    private let services: StoneServices
    private let panelStore = PanelStore()
    private let captureStore: CaptureStore
    private let browseStore: BrowseStore
    private let hotKeys = HotKeyCenter()
    private let hud = HUDController()

    private lazy var panel = QuickPanelController(
        panelStore: panelStore, capture: captureStore, browse: browseStore
    ) { [unowned self] intent in handle(intent) }

    public init(services: StoneServices) {
        self.services = services
        captureStore = CaptureStore(journal: services.journal)
        browseStore = BrowseStore(services: services)
    }

    /// Registers Stone's quick-capture chord and reports visibly when it cannot.
    @discardableResult
    public func start(captureShortcut: String) -> HotKeyStatus {
        let status = registerHotKey(captureShortcut)
        switch status {
        case .registered, .disabled: break
        case .invalid(let text):
            hud.show("Can't read the shortcut “\(text)” in Stone's config — use the menu bar", isError: true)
        case .unavailable(let display):
            hud.show("\(display) is taken (is Stone desktop running?) — use the menu bar", isError: true)
        }
        return status
    }

    public func toggle() {
        panel.isVisible ? panel.hide() : showCapture()
    }

    public func showCapture() {
        panelStore.screen = .capture
        panel.resetUndo()
        panel.present()
    }

    public func showNotes() {
        panelStore.screen = .browse
        panel.present()
        Task { await browseStore.prepare() }
    }

    public func showToday() {
        Task {
            do {
                guard let today = try await services.journal.today() else {
                    hud.show("Nothing written today yet", symbol: "calendar")
                    return
                }
                panelStore.screen = .browse
                panel.present()
                await browseStore.prepare(showing: today)
            } catch {
                hud.show(Self.describe(error), isError: true)
            }
        }
    }

    public func revealWorkspace() {
        NSWorkspace.shared.open(URL(fileURLWithPath: services.notes.workspaceLocation, isDirectory: true))
    }

    /// Stops new captures first, then lets every queued one reach disk before the process goes.
    public func prepareForTermination() async {
        hotKeys.unregisterAll()
        panel.hide()
        await captureStore.close()
    }

    private func registerHotKey(_ text: String) -> HotKeyStatus {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return .disabled }
        guard let shortcut = KeyShortcut(parsing: text) else { return .invalid(text) }
        let registered = hotKeys.register(shortcut) { [unowned self] in toggle() }
        return registered ? .registered(shortcut.display) : .unavailable(shortcut.display)
    }

    private func handle(_ intent: QuickPanel.KeyIntent) -> Bool {
        switch (intent, panelStore.screen) {
        case (.submit, .capture):
            submitCapture()
        case (.newline, .capture):
            panel.insertNewline()
        case (.submit, .browse):
            copyPreview()
        case (.newline, .browse):
            break
        case (.move(let delta), .browse):
            browseStore.move(by: delta)
        case (.move, .capture):
            return false
        case (.toggleBrowse, .capture):
            showNotes()
        case (.toggleBrowse, .browse), (.escape, .browse):
            showCapture()
        case (.escape, .capture), (.close, _):
            panel.hide()
        case (.today, _):
            showToday()
        }
        return true
    }

    /// Stone's quick-capture feel: the panel closes at once and the save finishes behind it.
    private func submitCapture() {
        guard let save = captureStore.submit() else { return }
        panel.resetUndo()
        panel.hide()
        Task {
            switch await save.value {
            case .success(let note): hud.show("Saved to \(note.title)")
            case .failure(let error): hud.show("Not saved — it's back in your draft. \(Self.describe(error))", isError: true)
            }
        }
    }

    /// Reads the selection again rather than trusting the preview, which may still be loading.
    private func copyPreview() {
        Task {
            guard let note = await browseStore.readSelection() else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(note.body, forType: .string)
            hud.show("Copied “\(note.title)”", symbol: "doc.on.doc")
        }
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case NoteError.notFound(let path): "“\(path.stem)” no longer exists."
        case NoteError.invalidPath, NoteError.invalidFolder: "The journal folder in Stone's config isn't a valid folder name."
        case let error as CocoaError where error.code == .fileWriteNoPermission: "Stone can't write to the workspace folder."
        default: error.localizedDescription
        }
    }
}
