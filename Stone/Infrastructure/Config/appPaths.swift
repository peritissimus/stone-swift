import Foundation

/// Stone desktop's config, shared rather than copied: both apps read one file.
func configFileURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/stone/config.json")
}

/// `STONE_WORKSPACE` overrides the configured folder for a single run, never persisted.
func resolveWorkspaceURL(_ configured: String) -> URL {
    let raw = ProcessInfo.processInfo.environment["STONE_WORKSPACE"] ?? configured
    let expanded = (raw as NSString).expandingTildeInPath
    let home = FileManager.default.homeDirectoryForCurrentUser
    let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : home.appendingPathComponent(expanded)
    return url.standardizedFileURL
}
