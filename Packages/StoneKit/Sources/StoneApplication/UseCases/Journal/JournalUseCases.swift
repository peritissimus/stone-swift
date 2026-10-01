import Foundation
import StoneDomain

public final class JournalUseCases: IJournalUseCases {
    private let captureEntry: CaptureToJournalUseCase
    private let getToday: GetTodayJournalUseCase

    init(capture: CaptureToJournalUseCase, today: GetTodayJournalUseCase) {
        self.captureEntry = capture
        self.getToday = today
    }

    public func capture(_ text: String, writtenAt: Date) async throws -> NoteEntity {
        try await captureEntry.execute(text, writtenAt: writtenAt)
    }
    public func today() async throws -> NoteEntity? { try await getToday.execute() }
}
