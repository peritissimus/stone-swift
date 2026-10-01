import Foundation
import Observation
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

    func start() async {
        let config = (try? await AppConfigRepository(file: configFileURL()).load()) ?? .standard
        let root = resolveWorkspaceURL(config.workspacePath)
        let policy = config.locationPolicy

        let repository = FileSystemNoteRepository(root: root)
        let clock = SystemClock()

        let shell = StoneShell(
            services: StoneServices(
                journal: createJournalUseCases(repository: repository, clock: clock, policy: policy),
                notes: createNoteUseCases(repository: repository, policy: policy),
                search: createSearchUseCases(repository: repository, policy: policy)))
        hotKeyStatus = shell.start(captureShortcut: config.captureShortcut)
        self.shell = shell
    }
}
