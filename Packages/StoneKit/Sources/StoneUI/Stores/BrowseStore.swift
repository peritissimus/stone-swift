import Foundation
import Observation
import StoneDomain

/// Looking back: recent notes, full-text search, and a read-only preview of the selection.
@MainActor
@Observable
final class BrowseStore {
    static let recentLimit = 50
    static let searchLimit = 50

    var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    private(set) var rows: [BrowseRow] = []
    private(set) var selectedPath: NotePath?
    private(set) var preview: NoteEntity?
    private(set) var focusToken = 0

    @ObservationIgnored private let services: StoneServices
    @ObservationIgnored private var recent: [BrowseRow] = []
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var previewGeneration = 0

    init(services: StoneServices) {
        self.services = services
    }

    /// Opens on the recent list; `note`, when given, is selected and previewed without a re-read.
    func prepare(showing note: NoteEntity? = nil) async {
        searchTask?.cancel()
        query = ""
        focusToken += 1
        // The panel outlives a show; the same note may have changed since it was last previewed.
        previewGeneration += 1
        selectedPath = nil
        preview = nil
        let listed = (try? await services.notes.listNotes()) ?? []
        recent = listed.prefix(Self.recentLimit).map { BrowseRow(note: $0, snippet: nil) }
        rows = recent
        if let note {
            previewGeneration += 1
            selectedPath = note.path
            preview = note
        } else {
            select(rows.first?.note.path)
        }
    }

    func move(by delta: Int) {
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.note.path == selectedPath } ?? -1
        select(rows[min(max(current + delta, 0), rows.count - 1)].note.path)
    }

    func select(_ path: NotePath?) {
        guard path != selectedPath || preview?.path != path else { return }
        selectedPath = path
        previewGeneration += 1
        let generation = previewGeneration
        guard let path else {
            preview = nil
            return
        }
        let notes = services.notes
        Task { [weak self] in
            let note = try? await notes.openNote(path)
            guard let self, self.previewGeneration == generation else { return }
            self.preview = note
        }
    }

    /// The selected note as it is on disk now — never a preview that is still loading or stale.
    func readSelection() async -> NoteEntity? {
        guard let path = selectedPath else { return nil }
        return try? await services.notes.openNote(path)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            show(recent)
            return
        }
        let search = services.search
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Theme.Motion.searchDebounce)
            guard !Task.isCancelled else { return }
            let hits = (try? await search.search(text, limit: Self.searchLimit)) ?? []
            guard !Task.isCancelled, let self else { return }
            self.show(hits.map { BrowseRow(note: $0.note, snippet: $0.snippet) })
        }
    }

    private func show(_ newRows: [BrowseRow]) {
        rows = newRows
        if !rows.contains(where: { $0.note.path == selectedPath }) { select(rows.first?.note.path) }
    }
}
