import StoneDomain

/// Reconciles the derived cache and keeps model work off the capture path.
public actor NoteSearchIndexer {
    private let repository: any INoteRepository
    private let policy: LocationPolicy
    private let index: any INoteSearchIndex
    private let embedder: (any ITextEmbedder)?
    private var textTask: Task<Void, Error>?
    private var textGeneration = 0
    private var embeddingTask: Task<Void, Never>?
    private var embeddingGeneration = 0
    private var hasRefreshed = false

    public init(
        repository: any INoteRepository, policy: LocationPolicy,
        index: any INoteSearchIndex, embedder: (any ITextEmbedder)? = nil
    ) {
        self.repository = repository
        self.policy = policy
        self.index = index
        self.embedder = embedder
    }

    /// Scans metadata; unchanged note bodies are never re-read.
    public func refresh() async throws {
        try Task.checkCancellation()
        let task = enqueueTextWork { try await self.reconcileFiles() }
        try await task.value
        try Task.checkCancellation()
    }

    /// The first search waits for initial indexing; later searches only wait for queued captures.
    public func prepareForSearch() async throws {
        try Task.checkCancellation()
        if let textTask { try await textTask.value }
        if !hasRefreshed { try await refresh() }
        try Task.checkCancellation()
    }

    /// A successful capture must not fail, or wait for an embedding, because its cache is unavailable.
    public func noteAdded(_ note: NoteEntity) async {
        _ = enqueueTextWork {
            try await self.indexCapturedNote(note)
        }
    }

    /// Waits for already queued work, without forcing retries when a model is unavailable.
    public func waitForPendingEmbeddings() async {
        while let task = textTask { _ = try? await task.value }
        while let task = embeddingTask { await task.value }
    }

    private func enqueueTextWork(_ operation: @escaping @Sendable () async throws -> Void) -> Task<Void, Error> {
        let previous = textTask
        textGeneration += 1
        let generation = textGeneration
        let task = Task {
            // A failed cache operation must not prevent a later repair or capture from being indexed.
            _ = try? await previous?.value
            do {
                try Task.checkCancellation()
                try await operation()
                self.finishTextWork(generation: generation)
            } catch {
                self.hasRefreshed = false
                self.finishTextWork(generation: generation)
                throw error
            }
        }
        textTask = task
        return task
    }

    private func finishTextWork(generation: Int) {
        if textGeneration == generation { textTask = nil }
    }

    private func reconcileFiles() async throws {
        let files = try await repository.listNotes()
        let cached = try await index.indexedFiles()
        let indexed = Dictionary(uniqueKeysWithValues: cached.map { ($0.path, $0.modifiedAt) })
        let currentPaths = Set(files.map(\.path))
        try await index.remove(cached.map(\.path).filter { !currentPaths.contains($0) })
        for file in files where indexed[file.path] != file.modifiedAt {
            try Task.checkCancellation()
            let source: String
            do {
                source = try await repository.read(file.path)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                // A disappearing or unreadable file must not block indexing every later note.
                let latestInfo: NoteFileInfo?
                do { latestInfo = try await repository.info(file.path) }
                catch is CancellationError { throw CancellationError() }
                catch { continue }
                if latestInfo == nil { try await index.remove([file.path]) }
                continue
            }
            try await index.upsert(NoteEntity(
                path: file.path, source: source, modifiedAt: file.modifiedAt, policy: policy))
        }
        hasRefreshed = true
        scheduleEmbeddings()
    }

    private func indexCapturedNote(_ note: NoteEntity) async throws {
        try await index.upsert(note)
        scheduleEmbeddings()
    }

    private func scheduleEmbeddings() {
        guard embedder != nil else { return }
        embeddingGeneration += 1
        startEmbeddingWorkerIfNeeded()
    }

    private func startEmbeddingWorkerIfNeeded() {
        guard embeddingTask == nil, let embedder else { return }
        embeddingTask = Task(priority: .utility) { await self.processEmbeddings(using: embedder) }
    }

    private func processEmbeddings(using embedder: any ITextEmbedder) async {
        var observedGeneration = embeddingGeneration
        var cursor: Int64?
        do {
            while !Task.isCancelled {
                let inputs = try await index.pendingEmbeddings(
                    modelIdentifier: embedder.modelIdentifier, afterID: cursor, limit: 16)
                if inputs.isEmpty {
                    if observedGeneration != embeddingGeneration {
                        observedGeneration = embeddingGeneration
                        cursor = nil
                        continue
                    }
                    break
                }
                for input in inputs {
                    try Task.checkCancellation()
                    cursor = input.id
                    do {
                        guard let embedding = try await embedder.embed(input.text) else { continue }
                        try Task.checkCancellation()
                        try await index.storeEmbedding(embedding, for: input)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // One unsupported chunk must not starve every later chunk in the queue.
                    }
                }
            }
        } catch {
            // Text is already committed. The next refresh retries interrupted or unavailable model work.
        }
        finishEmbeddingWork(observedGeneration: observedGeneration)
    }

    private func finishEmbeddingWork(observedGeneration: Int) {
        embeddingTask = nil
        // A capture can arrive while the worker awaits an empty batch or a failed model call.
        if observedGeneration != embeddingGeneration { startEmbeddingWorkerIfNeeded() }
    }
}
