import Foundation
import Synchronization
import StoneDomain

/// In-memory stand-in for the filesystem port.
final class InMemoryNoteRepository: INoteRepository {
    private let files = Mutex<[NotePath: (source: String, modifiedAt: Date)]>([:])

    init(_ seed: [String: String] = [:]) {
        files.withLock { store in
            for (index, (path, source)) in seed.sorted(by: { $0.key < $1.key }).enumerated() {
                store[try! NotePath(path)] = (source, Date(timeIntervalSince1970: TimeInterval(index)))
            }
        }
    }

    var locationDescription: String { "memory" }

    func listNotes() async throws -> [NoteFileInfo] {
        files.withLock { $0.map { NoteFileInfo(path: $0.key, modifiedAt: $0.value.modifiedAt) } }
    }

    func read(_ path: NotePath) async throws -> String {
        guard let file = files.withLock({ $0[path] }) else { throw NoteError.notFound(path) }
        return file.source
    }

    func info(_ path: NotePath) async throws -> NoteFileInfo? {
        files.withLock { $0[path].map { NoteFileInfo(path: path, modifiedAt: $0.modifiedAt) } }
    }

    func write(_ source: String, to path: NotePath) async throws {
        files.withLock { $0[path] = (source, Date(timeIntervalSince1970: 1_000_000)) }
    }

    func source(_ path: String) -> String? {
        files.withLock { $0[try! NotePath(path)]?.source }
    }
}

struct FixedClock: IClock {
    let now: Date
    let calendar: Calendar

    init(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 30) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        self.calendar = calendar
        self.now = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
