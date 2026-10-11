/// Derived note retrieval data; implementations preserve the shared database's note metadata.
public protocol INoteSearchIndex: Sendable {
    func indexedFiles() async throws -> [NoteFileInfo]
    func upsert(_ note: NoteEntity) async throws
    func remove(_ paths: [NotePath]) async throws
    /// Results are ordered by ascending id, allowing unavailable inputs to be skipped for this pass.
    func pendingEmbeddings(modelIdentifier: String, afterID: Int64?, limit: Int) async throws -> [NoteEmbeddingInput]
    /// Store only if the input still identifies the same text, so an old job cannot overwrite an edit.
    func storeEmbedding(_ embedding: TextEmbedding, for input: NoteEmbeddingInput) async throws
    func candidates(query: String, embedding: TextEmbedding?, limit: Int) async throws -> [SearchCandidate]
}

public extension INoteSearchIndex {
    func pendingEmbeddings(modelIdentifier: String, limit: Int) async throws -> [NoteEmbeddingInput] {
        try await pendingEmbeddings(modelIdentifier: modelIdentifier, afterID: nil, limit: limit)
    }
}
