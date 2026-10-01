import Foundation
import StoneDomain

/// Stone's quick capture: a timestamped paragraph appended to today's journal.
/// It appends to the file's exact text — frontmatter, headings and spacing stay byte-for-byte.
public final class CaptureToJournalUseCase: Sendable {
    private let repository: any INoteRepository
    private let clock: any IClock
    private let policy: LocationPolicy

    public init(repository: any INoteRepository, clock: any IClock, policy: LocationPolicy) {
        self.repository = repository
        self.clock = clock
        self.policy = policy
    }

    public func execute(_ text: String, writtenAt now: Date) async throws -> NoteEntity {
        let day = JournalDate(date: now, calendar: clock.calendar)
        let path = try policy.journalPath(for: day)
        let existing = try await repository.info(path) == nil ? nil : try await repository.read(path)
        let parts = clock.calendar.dateComponents([.hour, .minute], from: now)
        let time = ClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        let base = existing ?? JournalComposer.seed(for: day)
        let updated = JournalComposer.append(text, at: time, to: base)
        // A blank capture changes nothing, so it must not create the day's file either.
        if updated != base { try await repository.write(updated, to: path) }
        return NoteEntity(path: path, source: updated, modifiedAt: now, policy: policy)
    }
}
