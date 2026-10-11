import Foundation
import Observation
import OSLog
import StoneAdaptersOut
import StoneApplication
import StoneDomain
import StoneUI

/// The composition root: the only place that knows every concrete type.
/// Order: out adapters → use cases → the driving adapter.
@MainActor
@Observable
final class AppContainer {
    private(set) var shell: StoneShell?
    private(set) var hotKeyStatus: StoneShell.HotKeyStatus = .disabled
    @ObservationIgnored private var indexingTask: Task<Void, Never>?
    @ObservationIgnored private var models: DesktopModelService?
    private let logger = Logger(subsystem: "com.stone.swift", category: "search")

    func start() async {
        let config = (try? await AppConfigRepository(file: configFileURL()).load()) ?? .standard
        let root = resolveWorkspaceURL(config.workspacePath)
        let policy = config.locationPolicy

        let repository = FileSystemNoteRepository(root: root)
        let clock = SystemClock()

        let models: DesktopModelService?
        if let node = nodeExecutableURL(), let worker = desktopWorkerURL() {
            models = try? DesktopModelService(nodeURL: node, workerURL: worker, cacheURL: desktopModelCacheURL())
        } else {
            logger.notice("Desktop model worker or Node unavailable; keyword search remains available")
            models = nil
        }
        self.models = models
        let index: SQLiteNoteSearchIndex?
        do {
            index = try SQLiteNoteSearchIndex(databaseURL: searchDatabaseURL(), workspaceURL: root, policy: policy)
        } catch {
            logger.error("Search index unavailable; using file search: \(error.localizedDescription, privacy: .public)")
            index = nil
        }
        let indexer = index.map {
            NoteSearchIndexer(repository: repository, policy: policy, index: $0, embedder: models)
        }

        let shell = StoneShell(
            services: StoneServices(
                journal: createJournalUseCases(repository: repository, clock: clock, policy: policy, indexer: indexer),
                notes: createNoteUseCases(repository: repository, policy: policy),
                search: createSearchUseCases(
                    repository: repository, policy: policy, index: index, indexer: indexer,
                    embedder: models, reranker: models)))
        hotKeyStatus = shell.start(captureShortcut: config.captureShortcut)
        self.shell = shell

        indexingTask?.cancel()
        if let indexer {
            let logger = self.logger
            indexingTask = Task(priority: .utility) {
                while !Task.isCancelled {
                    do {
                        try await indexer.refresh()
                    } catch is CancellationError {
                        break
                    } catch {
                        logger.error("Search refresh failed; will retry: \(error.localizedDescription, privacy: .public)")
                    }
                    do { try await Task.sleep(for: .seconds(30)) }
                    catch { break }
                }
            }
        }
    }

    func stopSearch() async {
        indexingTask?.cancel()
        indexingTask = nil
        await models?.shutdown()
        models = nil
    }

    deinit { indexingTask?.cancel() }
}
