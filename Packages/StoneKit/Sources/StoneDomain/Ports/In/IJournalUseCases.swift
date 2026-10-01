import Foundation

/// What the app can do with daily notes: take a note, and look back at today's.
public protocol IJournalUseCases: Sendable {
    /// Appends a `[HH:MM]` entry to the journal of the day `writtenAt` falls on, creating it if needed.
    /// The caller stamps it, so a save that waits in a queue keeps the moment the note was taken.
    func capture(_ text: String, writtenAt: Date) async throws -> NoteEntity
    /// Today's journal as it is on disk; nil before the first note of the day. Never creates a file.
    func today() async throws -> NoteEntity?
}
