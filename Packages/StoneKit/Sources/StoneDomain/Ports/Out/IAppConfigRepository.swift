/// Read access to the shared Stone config.
public protocol IAppConfigRepository: Sendable {
    func load() async throws -> AppConfig
}
