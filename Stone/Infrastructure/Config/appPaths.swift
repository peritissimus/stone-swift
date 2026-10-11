import Foundation

/// Stone desktop's config, shared rather than copied: both apps read one file.
func configFileURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/stone/config.json")
}

/// `STONE_WORKSPACE` overrides the configured folder for a single run, never persisted.
func resolveWorkspaceURL(_ configured: String) -> URL {
    let raw = ProcessInfo.processInfo.environment["STONE_WORKSPACE"] ?? configured
    return expandedFileURL(raw).standardizedFileURL
}

/// The desktop app owns this schema and registers the workspaces it contains.
func searchDatabaseURL() -> URL {
    expandedFileURL(ProcessInfo.processInfo.environment["STONE_DATABASE_PATH"] ?? ".config/stone/stone-data/notes.db")
}

func desktopModelCacheURL() -> URL {
    expandedFileURL(ProcessInfo.processInfo.environment["STONE_ML_CACHE"] ?? ".config/stone/ml-cache")
}

func desktopWorkerURL() -> URL? {
    let environment = ProcessInfo.processInfo.environment
    if let override = environment["STONE_EMBEDDING_WORKER"] { return existingFile(override) }
    let suffix = "Stone.app/Contents/Resources/app.asar.unpacked/dist/main/workers/embedding.worker.cjs"
    let candidates = [
        "/Applications/" + suffix,
        "Applications/" + suffix,
        "projects/stone/dist/main/workers/embedding.worker.cjs",
    ]
    return candidates.compactMap(existingFile).first
}

func nodeExecutableURL() -> URL? {
    let environment = ProcessInfo.processInfo.environment
    if let override = environment["STONE_NODE_PATH"] {
        let url = expandedFileURL(override)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
    let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
    return directories.map { URL(fileURLWithPath: $0).appendingPathComponent("node") }
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }
}

private func expandedFileURL(_ raw: String) -> URL {
    let expanded = (raw as NSString).expandingTildeInPath
    return expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded)
        : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(expanded)
}

private func existingFile(_ raw: String) -> URL? {
    let url = expandedFileURL(raw)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
}
