import CSQLite
import Foundation
import StoneDomain

/// Uses Stone desktop's existing retrieval tables; Markdown remains the content source of truth.
public actor SQLiteNoteSearchIndex: INoteSearchIndex {
    private static let model = "Xenova/bge-small-en-v1.5"
    private static let dimensions = 384
    private static let vectorBytes = dimensions * MemoryLayout<UInt32>.size
    private let connection: SQLiteConnection
    private let workspaceID: String
    private let policy: LocationPolicy

    public init(databaseURL: URL, workspaceURL: URL, policy: LocationPolicy = .standard) throws {
        let connection = try SQLiteConnection(databaseURL: databaseURL)
        let workspaceID = try SQLiteDesktopSchema.workspaceID(in: connection, workspaceURL: workspaceURL)
        try connection.execute("PRAGMA foreign_keys = ON")
        try SQLiteDesktopSchema.prepareBookkeeping(in: connection)
        self.connection = connection
        self.workspaceID = workspaceID
        self.policy = policy
    }

    public func indexedFiles() async throws -> [NoteFileInfo] {
        let statement = try connection.prepare("""
            SELECT n.file_path, CASE WHEN s.content_hash = r.content_hash AND r.status IN ('pending', 'indexed')
                AND r.model = ? AND r.dimensions = ? AND r.chunk_count = (
                    SELECT count(*) FROM note_chunks c WHERE c.note_id = n.id AND c.workspace_id = n.workspace_id)
                THEN s.source_mtime ELSE NULL END
            FROM notes n LEFT JOIN stone_swift_index_state s ON s.note_id = n.id AND s.workspace_id = n.workspace_id
                LEFT JOIN note_index_records r ON r.note_id = n.id AND r.workspace_id = n.workspace_id
            WHERE n.workspace_id = ? AND n.is_deleted = 0 AND n.file_path IS NOT NULL ORDER BY n.file_path, n.created_at, n.id
            """)
        try statement.bind(Self.model, at: 1)
        try statement.bind(Int64(Self.dimensions), at: 2)
        try statement.bind(workspaceID, at: 3)
        var files: [NoteFileInfo] = []
        var paths: Set<NotePath> = []
        while try statement.step() {
            guard let path = try? NotePath(statement.string(at: 0)), paths.insert(path).inserted else { continue }
            let mtime = statement.isNull(at: 1) ? Date.distantPast : Date(timeIntervalSince1970: statement.double(at: 1))
            files.append(NoteFileInfo(path: path, modifiedAt: mtime))
        }
        return files
    }

    public func upsert(_ note: NoteEntity) async throws {
        let contentHash = NoteContentHasher.hash(note.source)
        try connection.transaction {
            let existing = try connection.prepare("""
                SELECT n.id, n.is_deleted, r.content_hash, n.title FROM notes n
                LEFT JOIN note_index_records r ON r.note_id = n.id AND r.workspace_id = n.workspace_id
                WHERE n.workspace_id = ? AND n.file_path = ?
                ORDER BY n.is_deleted DESC, n.created_at, n.id LIMIT 1
                """)
            try existing.bind(workspaceID, at: 1)
            try existing.bind(note.path.value, at: 2)
            let exists = try existing.step()
            // A stale file must never restore a note that desktop moved to trash.
            if exists && existing.integer(at: 1) != 0 { return }
            let noteID = exists ? existing.string(at: 0) : UUID().uuidString.lowercased()
            let unchangedSource = exists && existing.string(at: 2) == contentHash
            let extractedTitle = note.isJournal ? note.path.stem : DesktopNoteTitleExtractor.title(source: note.source)
            let title = unchangedSource ? existing.string(at: 3)
                : (extractedTitle ?? (exists ? existing.string(at: 3) : note.path.stem))
            let sameContent = try reusableContent(noteID: noteID, hash: contentHash)
            if !exists {
                let insert = try connection.prepare("""
                    INSERT INTO notes(id, title, file_path, workspace_id, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """)
                try insert.bind(noteID, at: 1)
                try insert.bind(title, at: 2)
                try insert.bind(note.path.value, at: 3)
                try insert.bind(workspaceID, at: 4)
                try insert.bind(Int64(note.modifiedAt.timeIntervalSince1970.rounded(.down)), at: 5)
                try insert.bind(Int64(note.modifiedAt.timeIntervalSince1970.rounded(.down)), at: 6)
                _ = try insert.step()
            } else if !unchangedSource {
                // Never replace the desktop note row: flags, notebook, tags, and topics belong to desktop.
                let update = try connection.prepare("UPDATE notes SET title = ?, updated_at = ? WHERE id = ? AND workspace_id = ? AND is_deleted = 0")
                try update.bind(title, at: 1)
                try update.bind(Int64(note.modifiedAt.timeIntervalSince1970.rounded(.down)), at: 2)
                try update.bind(noteID, at: 3)
                try update.bind(workspaceID, at: 4)
                _ = try update.step()
            }
            if !sameContent { try replaceChunks(of: note, noteID: noteID, title: title, hash: contentHash) }
            let state = try connection.prepare("""
                INSERT INTO stone_swift_index_state(note_id, workspace_id, source_mtime, content_hash) VALUES (?, ?, ?, ?)
                ON CONFLICT(note_id) DO UPDATE SET workspace_id = excluded.workspace_id,
                    source_mtime = excluded.source_mtime, content_hash = excluded.content_hash
                """)
            try state.bind(noteID, at: 1)
            try state.bind(workspaceID, at: 2)
            try state.bind(note.modifiedAt.timeIntervalSince1970, at: 3)
            try state.bind(contentHash, at: 4)
            _ = try state.step()
        }
    }

    public func remove(_ paths: [NotePath]) async throws {
        guard !paths.isEmpty else { return }
        try connection.transaction {
            let lookup = try connection.prepare("SELECT id FROM notes WHERE workspace_id = ? AND file_path = ?")
            for path in paths {
                try lookup.bind(workspaceID, at: 1)
                try lookup.bind(path.value, at: 2)
                var ids: [String] = []
                while try lookup.step() { ids.append(lookup.string(at: 0)) }
                try lookup.reset()
                for id in ids {
                    for table in ["note_chunks_fts", "note_chunks", "note_index_records", "stone_swift_index_state"] {
                        let remove = try connection.prepare("DELETE FROM \(table) WHERE note_id = ? AND workspace_id = ?")
                        try remove.bind(id, at: 1)
                        try remove.bind(workspaceID, at: 2)
                        _ = try remove.step()
                    }
                }
            }
        }
    }

    public func pendingEmbeddings(modelIdentifier: String, afterID: Int64?, limit: Int) async throws -> [NoteEmbeddingInput] {
        guard modelIdentifier == Self.model, limit > 0 else { return [] }
        let statement = try connection.prepare("""
            SELECT c.rowid, c.text, c.id FROM note_chunks c
            JOIN notes n ON n.id = c.note_id AND n.workspace_id = c.workspace_id
            JOIN note_index_records r ON r.note_id = c.note_id AND r.workspace_id = c.workspace_id
            WHERE c.workspace_id = ? AND n.is_deleted = 0 AND r.model = ? AND r.dimensions = ?
                AND r.status IN ('pending', 'indexed') AND (c.embedding IS NULL OR length(c.embedding) != ?)
                AND c.rowid > ? ORDER BY c.rowid LIMIT ?
            """)
        try statement.bind(workspaceID, at: 1)
        try statement.bind(modelIdentifier, at: 2)
        try statement.bind(Int64(Self.dimensions), at: 3)
        try statement.bind(Int64(Self.vectorBytes), at: 4)
        try statement.bind(afterID ?? 0, at: 5)
        try statement.bind(Int64(min(limit, 1_000)), at: 6)
        var pending: [NoteEmbeddingInput] = []
        while try statement.step() {
            pending.append(NoteEmbeddingInput(id: statement.integer(at: 0), text: statement.string(at: 1), key: statement.string(at: 2)))
        }
        return pending
    }

    public func storeEmbedding(_ embedding: TextEmbedding, for input: NoteEmbeddingInput) async throws {
        guard embedding.modelIdentifier == Self.model, embedding.vector.count == Self.dimensions,
              Self.normalized(embedding.vector) != nil else {
            throw SQLiteDatabaseError(code: SQLITE_MISMATCH, message: "Stone requires a finite, nonzero BGE 384-dimensional embedding")
        }
        let vector = embedding.vector.map(Float.init)
        guard vector.allSatisfy(\.isFinite), vector.contains(where: { $0 != 0 }) else {
            throw SQLiteDatabaseError(code: SQLITE_MISMATCH, message: "Embedding cannot be represented as Float32")
        }
        guard let key = input.key else { return }
        var data = Data(capacity: Self.vectorBytes)
        for value in vector {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        try connection.transaction {
            let target = try connection.prepare("""
                SELECT c.note_id FROM note_chunks c
                JOIN notes n ON n.id = c.note_id AND n.workspace_id = c.workspace_id
                JOIN note_index_records r ON r.note_id = c.note_id AND r.workspace_id = c.workspace_id
                WHERE c.rowid = ? AND c.id = ? AND c.text = ? AND c.content_hash = ? AND c.workspace_id = ?
                    AND n.is_deleted = 0 AND r.model = ? AND r.dimensions = ? AND r.status IN ('pending', 'indexed')
                """)
            try target.bind(input.id, at: 1)
            try target.bind(key, at: 2)
            try target.bind(input.text, at: 3)
            try target.bind(NoteContentHasher.hash(input.text), at: 4)
            try target.bind(workspaceID, at: 5)
            try target.bind(Self.model, at: 6)
            try target.bind(Int64(Self.dimensions), at: 7)
            guard try target.step() else { return }
            let noteID = target.string(at: 0)
            let update = try connection.prepare("UPDATE note_chunks SET embedding = ?, updated_at = ? WHERE id = ? AND workspace_id = ?")
            try update.bind(data, at: 1)
            try update.bind(Int64(Date().timeIntervalSince1970.rounded(.down)), at: 2)
            try update.bind(key, at: 3)
            try update.bind(workspaceID, at: 4)
            _ = try update.step()
            let status = try connection.prepare("""
                UPDATE note_index_records SET status = 'indexed', indexed_at = ?, error = NULL
                WHERE note_id = ? AND workspace_id = ? AND NOT EXISTS (
                    SELECT 1 FROM note_chunks WHERE note_id = ? AND workspace_id = ?
                        AND (embedding IS NULL OR length(embedding) != ?))
                """)
            try status.bind(Int64(Date().timeIntervalSince1970.rounded(.down)), at: 1)
            try status.bind(noteID, at: 2)
            try status.bind(workspaceID, at: 3)
            try status.bind(noteID, at: 4)
            try status.bind(workspaceID, at: 5)
            try status.bind(Int64(Self.vectorBytes), at: 6)
            _ = try status.step()
        }
    }

    public func candidates(query: String, embedding: TextEmbedding?, limit: Int) async throws -> [SearchCandidate] {
        guard limit > 0 else { return [] }
        let bound = min(limit, 500)
        let lexical = try lexicalCandidates(query: query, limit: bound)
        guard let embedding, embedding.modelIdentifier == Self.model, embedding.vector.count == Self.dimensions,
              let vector = Self.normalized(embedding.vector) else { return lexical }
        let semantic = try semanticCandidates(vector: vector, limit: bound)
        var combined = Dictionary(uniqueKeysWithValues: lexical.map { ($0.note.path, $0) })
        var semanticRanks: [NotePath: Int] = [:]
        for (offset, candidate) in semantic.enumerated() {
            semanticRanks[candidate.note.path] = offset + 1
            combined[candidate.note.path] = SearchCandidate(
                note: candidate.note, text: combined[candidate.note.path]?.text ?? candidate.text,
                lexicalRank: combined[candidate.note.path]?.lexicalRank, semanticSimilarity: candidate.semanticSimilarity)
        }
        func score(_ candidate: SearchCandidate) -> Double {
            (candidate.lexicalRank.map { 1 / (60 + Double($0)) } ?? 0)
                + (semanticRanks[candidate.note.path].map { 1 / (60 + Double($0)) } ?? 0)
        }
        return Array(combined.values.sorted {
            if score($0) != score($1) { return score($0) > score($1) }
            if ($0.lexicalRank != nil) != ($1.lexicalRank != nil) { return $0.lexicalRank != nil }
            if $0.note.modifiedAt != $1.note.modifiedAt { return $0.note.modifiedAt > $1.note.modifiedAt }
            return $0.note.path < $1.note.path
        }.prefix(bound))
    }

    private func reusableContent(noteID: String, hash: String) throws -> Bool {
        let record = try connection.prepare("""
            SELECT r.content_hash FROM note_index_records r WHERE r.note_id = ? AND r.workspace_id = ?
                AND r.content_hash = ? AND r.model = ? AND r.dimensions = ? AND r.status IN ('pending', 'indexed')
                AND r.chunk_count = (SELECT count(*) FROM note_chunks c WHERE c.note_id = r.note_id AND c.workspace_id = r.workspace_id)
            """)
        try record.bind(noteID, at: 1)
        try record.bind(workspaceID, at: 2)
        try record.bind(hash, at: 3)
        try record.bind(Self.model, at: 4)
        try record.bind(Int64(Self.dimensions), at: 5)
        return try record.step()
    }

    private func replaceChunks(of note: NoteEntity, noteID: String, title: String, hash: String) throws {
        for table in ["note_chunks_fts", "note_chunks"] {
            let clear = try connection.prepare("DELETE FROM \(table) WHERE note_id = ? AND workspace_id = ?")
            try clear.bind(noteID, at: 1)
            try clear.bind(workspaceID, at: 2)
            _ = try clear.step()
        }
        let chunks = DesktopNoteChunker.chunks(source: note.source)
        let insert = try connection.prepare("""
            INSERT INTO note_chunks(id, note_id, workspace_id, chunk_index, heading_path, text, content_hash,
                token_count, embedding, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?)
            """)
        let fts = try connection.prepare("""
            INSERT INTO note_chunks_fts(chunk_id, note_id, workspace_id, title, heading_path, text) VALUES (?, ?, ?, ?, ?, ?)
            """)
        for (offset, chunk) in chunks.enumerated() {
            let id = UUID().uuidString.lowercased()
            let headingData = try JSONEncoder().encode(chunk.headingPath)
            let heading = String(decoding: headingData, as: UTF8.self)
            try insert.bind(id, at: 1)
            try insert.bind(noteID, at: 2)
            try insert.bind(workspaceID, at: 3)
            try insert.bind(Int64(offset), at: 4)
            try insert.bind(heading, at: 5)
            try insert.bind(chunk.text, at: 6)
            try insert.bind(NoteContentHasher.hash(chunk.text), at: 7)
            try insert.bind(Int64(chunk.tokenCount), at: 8)
            try insert.bind(Int64(note.modifiedAt.timeIntervalSince1970.rounded(.down)), at: 9)
            try insert.bind(Int64(note.modifiedAt.timeIntervalSince1970.rounded(.down)), at: 10)
            _ = try insert.step()
            try insert.reset()
            try fts.bind(id, at: 1)
            try fts.bind(noteID, at: 2)
            try fts.bind(workspaceID, at: 3)
            try fts.bind(title, at: 4)
            try fts.bind(chunk.headingPath.joined(separator: " › "), at: 5)
            try fts.bind(chunk.text, at: 6)
            _ = try fts.step()
            try fts.reset()
        }
        let record = try connection.prepare("""
            INSERT INTO note_index_records(note_id, workspace_id, content_hash, chunk_count, indexed_at, model, dimensions, status, error)
            VALUES (?, ?, ?, ?, NULL, ?, ?, ?, NULL)
            ON CONFLICT(note_id) DO UPDATE SET content_hash = excluded.content_hash, chunk_count = excluded.chunk_count,
                indexed_at = excluded.indexed_at, model = excluded.model, dimensions = excluded.dimensions,
                status = excluded.status, error = NULL
            """)
        try record.bind(noteID, at: 1)
        try record.bind(workspaceID, at: 2)
        try record.bind(hash, at: 3)
        try record.bind(Int64(chunks.count), at: 4)
        try record.bind(Self.model, at: 5)
        try record.bind(Int64(Self.dimensions), at: 6)
        try record.bind(chunks.isEmpty ? "indexed" : "pending", at: 7)
        _ = try record.step()
        if chunks.isEmpty {
            let completed = try connection.prepare("UPDATE note_index_records SET indexed_at = ? WHERE note_id = ? AND workspace_id = ?")
            try completed.bind(Int64(Date().timeIntervalSince1970.rounded(.down)), at: 1)
            try completed.bind(noteID, at: 2)
            try completed.bind(workspaceID, at: 3)
            _ = try completed.step()
        }
    }

    private func lexicalCandidates(query: String, limit: Int) throws -> [SearchCandidate] {
        let tokenCharacters = CharacterSet.alphanumerics.union(.nonBaseCharacters)
        let terms = query.components(separatedBy: tokenCharacters.inverted).filter { !$0.isEmpty }.prefix(32)
        guard !terms.isEmpty else { return [] }
        let match = terms.map { "\"\($0)\"*" }.joined(separator: " AND ")
        let statement = try connection.prepare("""
            SELECT n.file_path, n.title, n.updated_at, c.text
            FROM note_chunks_fts JOIN note_chunks c ON c.id = note_chunks_fts.chunk_id
                AND c.workspace_id = note_chunks_fts.workspace_id AND c.note_id = note_chunks_fts.note_id
            JOIN notes n ON n.id = c.note_id AND n.workspace_id = c.workspace_id
            WHERE note_chunks_fts MATCH ? AND c.workspace_id = ? AND n.is_deleted = 0
            ORDER BY bm25(note_chunks_fts, 0, 0, 0, 5.0, 2.0, 1.0), n.updated_at DESC, n.file_path, c.chunk_index LIMIT ?
            """)
        try statement.bind(match, at: 1)
        try statement.bind(workspaceID, at: 2)
        try statement.bind(Int64(limit * 8), at: 3)
        var result: [SearchCandidate] = []
        var paths: Set<NotePath> = []
        while try statement.step() {
            try Task.checkCancellation()
            guard let note = summary(from: statement), paths.insert(note.path).inserted else { continue }
            result.append(SearchCandidate(note: note, text: statement.string(at: 3), lexicalRank: result.count + 1, semanticSimilarity: nil))
            if result.count >= limit { break }
        }
        if result.count < limit {
            // Desktop intentionally emits no chunks for heading-only notes; keep their titles searchable.
            let predicates = terms.map { _ in "n.title LIKE ? ESCAPE '\\'" }.joined(separator: " AND ")
            let titles = try connection.prepare("""
                SELECT n.file_path, n.title, n.updated_at FROM notes n
                JOIN note_index_records r ON r.note_id = n.id AND r.workspace_id = n.workspace_id
                WHERE n.workspace_id = ? AND n.is_deleted = 0 AND r.chunk_count = 0 AND r.status = 'indexed'
                    AND \(predicates) ORDER BY n.updated_at DESC, n.file_path LIMIT ?
                """)
            try titles.bind(workspaceID, at: 1)
            for (offset, term) in terms.enumerated() { try titles.bind("%\(term)%", at: Int32(offset + 2)) }
            try titles.bind(Int64(limit - result.count), at: Int32(terms.count + 2))
            while try titles.step() {
                guard let note = summary(from: titles), paths.insert(note.path).inserted else { continue }
                result.append(SearchCandidate(note: note, text: note.title, lexicalRank: result.count + 1, semanticSimilarity: nil))
            }
        }
        return result
    }

    private func semanticCandidates(vector: [Double], limit: Int) throws -> [SearchCandidate] {
        let statement = try connection.prepare("""
            SELECT n.file_path, n.title, n.updated_at, c.text, c.embedding FROM note_chunks c
            JOIN notes n ON n.id = c.note_id AND n.workspace_id = c.workspace_id
            JOIN note_index_records r ON r.note_id = c.note_id AND r.workspace_id = c.workspace_id
            WHERE c.workspace_id = ? AND n.is_deleted = 0 AND r.model = ? AND r.dimensions = ?
                AND r.status IN ('pending', 'indexed') AND length(c.embedding) = ? ORDER BY n.file_path, c.chunk_index
            """)
        try statement.bind(workspaceID, at: 1)
        try statement.bind(Self.model, at: 2)
        try statement.bind(Int64(Self.dimensions), at: 3)
        try statement.bind(Int64(Self.vectorBytes), at: 4)
        var result: [SearchCandidate] = []
        var bestForNote: SearchCandidate?
        func retain(_ candidate: SearchCandidate) {
            result.append(candidate)
            result.sort {
                if $0.semanticSimilarity != $1.semanticSimilarity { return ($0.semanticSimilarity ?? 0) > ($1.semanticSimilarity ?? 0) }
                return $0.note.path < $1.note.path
            }
            if result.count > limit { result.removeLast() }
        }
        while try statement.step() {
            try Task.checkCancellation()
            let data = statement.data(at: 4)
            let decoded = data.withUnsafeBytes { bytes in
                stride(from: 0, to: bytes.count, by: MemoryLayout<UInt32>.size).map {
                    Double(Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: $0, as: UInt32.self))))
                }
            }
            guard let stored = Self.normalized(decoded), let note = summary(from: statement) else { continue }
            let similarity = max(-1, min(1, zip(stored, vector).reduce(0) { $0 + $1.0 * $1.1 }))
            guard similarity >= 0.45 else { continue }
            let candidate = SearchCandidate(note: note, text: statement.string(at: 3), lexicalRank: nil, semanticSimilarity: similarity)
            if let best = bestForNote, best.note.path != note.path { retain(best); bestForNote = nil }
            if bestForNote == nil || similarity > (bestForNote?.semanticSimilarity ?? 0) { bestForNote = candidate }
        }
        if let bestForNote { retain(bestForNote) }
        return result
    }

    private func summary(from statement: SQLiteStatement) -> NoteSummary? {
        guard let path = try? NotePath(statement.string(at: 0)) else { return nil }
        return NoteSummary(path: path, title: statement.string(at: 1),
                           modifiedAt: Date(timeIntervalSince1970: statement.double(at: 2)), isJournal: policy.isJournal(path))
    }

    private static func normalized(_ vector: [Double]) -> [Double]? {
        guard vector.count == dimensions, vector.allSatisfy(\.isFinite),
              let scale = vector.map({ abs($0) }).max(), scale > 0 else { return nil }
        let scaled = vector.map { $0 / scale }
        let norm = sqrt(scaled.reduce(0) { $0 + $1 * $1 })
        guard norm.isFinite, norm > 0 else { return nil }
        return scaled.map { $0 / norm }
    }
}
