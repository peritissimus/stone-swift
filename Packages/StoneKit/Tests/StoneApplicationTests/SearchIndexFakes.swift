import Foundation
import StoneDomain

enum SearchTestError: Error { case unavailable }

actor SearchTestRepository: INoteRepository {
    nonisolated let locationDescription = "memory"
    private var files: [NotePath: (String, Date)] = [:]
    private(set) var readCount = 0
    private(set) var writeCount = 0
    var failsWrites = false
    private var failsListing = false
    private var unreadable: Set<NotePath> = []
    private var blockedPath: NotePath?
    private var blockedRead: CheckedContinuation<Void, Never>?
    private var readStarted: CheckedContinuation<Void, Never>?

    init(_ seed: [String: String] = [:]) {
        for (path, text) in seed { files[try! NotePath(path)] = (text, Date(timeIntervalSince1970: 1)) }
    }

    func listNotes() throws -> [NoteFileInfo] {
        if failsListing { throw SearchTestError.unavailable }
        return files.map { NoteFileInfo(path: $0.key, modifiedAt: $0.value.1) }.sorted { $0.path < $1.path }
    }
    func read(_ path: NotePath) async throws -> String {
        readCount += 1
        if unreadable.contains(path) { throw SearchTestError.unavailable }
        guard let file = files[path] else { throw NoteError.notFound(path) }
        if blockedPath == path {
            blockedPath = nil
            await withCheckedContinuation { continuation in
                blockedRead = continuation
                readStarted?.resume()
                readStarted = nil
            }
        }
        return file.0
    }
    func info(_ path: NotePath) -> NoteFileInfo? { files[path].map { NoteFileInfo(path: path, modifiedAt: $0.1) } }
    func write(_ source: String, to path: NotePath) throws {
        if failsWrites { throw SearchTestError.unavailable }
        writeCount += 1
        files[path] = (source, Date(timeIntervalSince1970: Double(writeCount + 1)))
    }
    func remove(_ raw: String) { files.removeValue(forKey: try! NotePath(raw)) }
    func failWrites() { failsWrites = true }
    func failListing() { failsListing = true }
    func failReads(_ raw: String) { unreadable.insert(try! NotePath(raw)) }
    func blockNextRead(_ raw: String) { blockedPath = try! NotePath(raw) }
    func waitUntilReadBlocked() async {
        if blockedRead != nil { return }
        await withCheckedContinuation { readStarted = $0 }
    }
    func releaseRead() { blockedRead?.resume(); blockedRead = nil }
}

actor SearchTestIndex: INoteSearchIndex {
    private(set) var notes: [NotePath: NoteEntity] = [:]
    private var inputs: [Int64: (NotePath, String)] = [:]
    private var vectors: [Int64: TextEmbedding] = [:]
    private var nextID: Int64 = 0
    private(set) var upsertCount = 0
    private(set) var storedEmbeddings = 0
    private(set) var attemptedEmbeddings = 0
    private(set) var candidateCalls = 0
    private var fails = false

    func fail() { fails = true }
    func recover() { fails = false }
    func indexedFiles() throws -> [NoteFileInfo] {
        if fails { throw SearchTestError.unavailable }
        return notes.values.map { NoteFileInfo(path: $0.path, modifiedAt: $0.modifiedAt) }
    }
    func upsert(_ note: NoteEntity) throws {
        if fails { throw SearchTestError.unavailable }
        upsertCount += 1
        notes[note.path] = note
        for id in inputs.keys where inputs[id]?.0 == note.path { inputs.removeValue(forKey: id); vectors.removeValue(forKey: id) }
        nextID += 1
        inputs[nextID] = (note.path, note.title + "\n" + note.body)
    }
    func remove(_ paths: [NotePath]) {
        for path in paths {
            notes.removeValue(forKey: path)
            for id in inputs.keys where inputs[id]?.0 == path { inputs.removeValue(forKey: id); vectors.removeValue(forKey: id) }
        }
    }
    func pendingEmbeddings(modelIdentifier: String, afterID: Int64?, limit: Int) -> [NoteEmbeddingInput] {
        inputs.keys.sorted().filter { (afterID == nil || $0 > afterID!) && vectors[$0]?.modelIdentifier != modelIdentifier }.prefix(limit).map {
            NoteEmbeddingInput(id: $0, text: inputs[$0]!.1)
        }
    }
    func storeEmbedding(_ embedding: TextEmbedding, for input: NoteEmbeddingInput) {
        attemptedEmbeddings += 1
        guard inputs[input.id]?.1 == input.text else { return }
        storedEmbeddings += 1
        vectors[input.id] = embedding
    }
    func candidates(query: String, embedding: TextEmbedding?, limit: Int) throws -> [SearchCandidate] {
        candidateCalls += 1
        if fails { throw SearchTestError.unavailable }
        return notes.values.filter { NoteSearchScorer.score(query: query, title: $0.title, body: $0.body) != nil }.map {
            SearchCandidate(note: $0.summary, text: $0.body, lexicalRank: 1, semanticSimilarity: nil)
        }
    }
}

actor BlockingSearchEmbedder: ITextEmbedder {
    nonisolated let modelIdentifier = "test-v1"
    private var blocked: CheckedContinuation<TextEmbedding?, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    private(set) var active = 0
    private(set) var maxActive = 0

    func embed(_ text: String) async -> TextEmbedding? {
        calls += 1
        active += 1
        maxActive = max(maxActive, active)
        defer { active -= 1 }
        if calls == 1 {
            return await withCheckedContinuation { continuation in
                blocked = continuation
                started?.resume()
                started = nil
            }
        }
        return TextEmbedding(modelIdentifier: modelIdentifier, vector: [1, 0])
    }
    func waitUntilStarted() async {
        if calls > 0 { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() {
        blocked?.resume(returning: TextEmbedding(modelIdentifier: modelIdentifier, vector: [1, 0]))
        blocked = nil
    }
}

actor UnavailableSearchEmbedder: ITextEmbedder {
    nonisolated let modelIdentifier = "unavailable"
    private(set) var calls = 0
    func embed(_ text: String) -> TextEmbedding? { calls += 1; return nil }
}

struct FailingSearchEmbedder: ITextEmbedder {
    let modelIdentifier = "failed"
    let cancelled: Bool
    func embed(_ text: String) throws -> TextEmbedding? {
        if cancelled { throw CancellationError() }
        throw SearchTestError.unavailable
    }
}

actor SelectiveSearchEmbedder: ITextEmbedder {
    nonisolated let modelIdentifier = "selective"
    private(set) var calls = 0
    func embed(_ text: String) -> TextEmbedding? {
        calls += 1
        return text.contains("unsupported") ? nil : TextEmbedding(modelIdentifier: modelIdentifier, vector: [1, 0])
    }
}
