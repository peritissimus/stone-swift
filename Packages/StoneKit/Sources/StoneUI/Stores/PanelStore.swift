import Observation

/// Which screen the one Stone panel shows. It always opens on capture.
@MainActor
@Observable
final class PanelStore {
    enum Screen: Equatable {
        case capture
        case browse
    }

    var screen: Screen = .capture
}
