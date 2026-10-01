import Foundation
import StoneDomain

/// Reads Stone desktop's own `~/.config/stone/config.json` — the one config both apps share.
/// Read-only: Stone rewrites and normalizes that file, so this app never writes it.
public final class AppConfigRepository: IAppConfigRepository {
    private let file: URL

    public init(file: URL) {
        self.file = file
    }

    /// A missing file or key reads as Stone's own default, as its normalizer does.
    public func load() async throws -> AppConfig {
        guard let data = try? Data(contentsOf: file) else { return .standard }
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let fallback = AppConfig.standard
        let workspace = root["workspace"] as? [String: Any]
        let policy = (root["notes"] as? [String: Any])?["locationPolicy"] as? [String: Any]
        let capture = root["quickCapture"] as? [String: Any]
        return AppConfig(
            workspacePath: Self.text(workspace?["defaultWorkspacePath"]) ?? fallback.workspacePath,
            locationPolicy: LocationPolicy(
                journalFolder: Self.text(policy?["journalFolder"]) ?? fallback.locationPolicy.journalFolder),
            // An empty shortcut is Stone's "no global hotkey", so it passes through as-is.
            captureShortcut: capture?["shortcut"] as? String ?? fallback.captureShortcut)
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String, !string.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return string
    }
}
