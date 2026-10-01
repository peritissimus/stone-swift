import Foundation
import Observation
import StoneDomain

/// The quick note being written. Nothing typed is lost: the draft survives closing and quitting,
/// and a submitted note stays on disk in `pendingKey` until the journal write succeeds.
@MainActor
@Observable
final class CaptureStore {
    static let draftKey = "quickCaptureDraft"
    static let pendingKey = "quickCapturePending"

    var draft: String {
        didSet { persistDraft() }
    }

    @ObservationIgnored private let journal: any IJournalUseCases
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    /// The most recent save; each one waits for the one before, so appends land in order.
    @ObservationIgnored private(set) var pending: Task<Void, Never>?
    @ObservationIgnored private var inFlight = 0
    /// Failures wait until the queue drains, then return to the draft in the order they were written.
    @ObservationIgnored private var failed: [String] = []
    @ObservationIgnored private var isClosed = false

    init(journal: any IJournalUseCases, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.journal = journal
        self.defaults = defaults
        self.now = now
        // Notes submitted but never confirmed written (a crash, a forced quit) come back first.
        let unsaved = defaults.stringArray(forKey: Self.pendingKey) ?? []
        draft = Self.join(unsaved + [defaults.string(forKey: Self.draftKey) ?? ""])
        defaults.removeObject(forKey: Self.pendingKey)
        persistDraft()
    }

    /// Clears the draft at once so the panel can close, then saves in the background.
    /// Nil when there is nothing to save or the app is quitting.
    func submit() -> Task<Result<NoteEntity, any Error>, Never>? {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isClosed else { return nil }
        let writtenAt = now()
        markPending(text)
        draft = ""
        inFlight += 1
        let previous = pending
        let journal = journal
        let save = Task { [weak self] () -> Result<NoteEntity, any Error> in
            await previous?.value
            let result: Result<NoteEntity, any Error>
            do {
                result = .success(try await journal.capture(text, writtenAt: writtenAt))
            } catch {
                result = .failure(error)
            }
            self?.finish(text, result)
            return result
        }
        pending = Task { _ = await save.value }
        return save
    }

    /// Refuses new captures, then waits until every queued save has finished.
    func close() async {
        isClosed = true
        while inFlight > 0 { await pending?.value }
    }

    private func finish(_ text: String, _ result: Result<NoteEntity, any Error>) {
        inFlight -= 1
        if case .failure = result { failed.append(text) }
        unmarkPending(text)
        guard inFlight == 0, !failed.isEmpty else { return }
        draft = Self.join(failed + [draft])
        failed = []
    }

    private func markPending(_ text: String) {
        defaults.set((defaults.stringArray(forKey: Self.pendingKey) ?? []) + [text], forKey: Self.pendingKey)
    }

    private func unmarkPending(_ text: String) {
        var list = defaults.stringArray(forKey: Self.pendingKey) ?? []
        if let index = list.firstIndex(of: text) { list.remove(at: index) }
        list.isEmpty ? defaults.removeObject(forKey: Self.pendingKey) : defaults.set(list, forKey: Self.pendingKey)
    }

    private func persistDraft() {
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.removeObject(forKey: Self.draftKey)
        } else {
            defaults.set(draft, forKey: Self.draftKey)
        }
    }

    private static func join(_ parts: [String]) -> String {
        parts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n\n")
    }
}
