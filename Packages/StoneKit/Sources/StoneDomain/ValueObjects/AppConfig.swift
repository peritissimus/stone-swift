/// The slice of Stone desktop's config this app reads. Stone owns the file; nothing here writes it.
public struct AppConfig: Hashable, Sendable {
    /// Absolute, `~/`-prefixed, or relative to the home folder (Stone's default is `NoteBook`).
    public var workspacePath: String
    public var locationPolicy: LocationPolicy
    /// Stone's `quickCapture.shortcut`, spelled like `Alt+Space`; empty means no global hotkey.
    public var captureShortcut: String

    public static let standard = AppConfig(
        workspacePath: "NoteBook", locationPolicy: .standard, captureShortcut: "Alt+Space")

    public init(workspacePath: String, locationPolicy: LocationPolicy, captureShortcut: String) {
        self.workspacePath = workspacePath
        self.locationPolicy = locationPolicy
        self.captureShortcut = captureShortcut
    }
}
