import Foundation
import Testing
import StoneDomain
@testable import StoneAdaptersOut

struct SQLiteNoteSearchIndexTests {
    @Test func changedAndNewNoteTitlesFollowDesktopHeadingAndFirstLineRules() async throws {
        let fixture = try SQLiteDesktopFixture()
        defer { fixture.cleanUp() }
        try fixture.seed(vector: fixture.vector())
        let index = try fixture.index()
        try await index.upsert(fixture.note(source: "Introductory paragraph\n\n## Second level title\n\nUpdated body."))
        #expect(try fixture.scalar("SELECT title FROM notes WHERE id = 'existing'") == "Second level title")
        try await index.upsert(fixture.note("new.md", source: "First line becomes the title\n\nSome details."))
        #expect(try fixture.scalar("SELECT title FROM notes WHERE file_path = 'new.md'") == "First line becomes the title")
    }

    @Test func workspaceAliasesResolveSafelyAndAmbiguousAliasesRequireExactPath() throws {
        let fixture = try SQLiteDesktopFixture()
        defer { fixture.cleanUp() }
        let alias = fixture.root.appendingPathComponent("linked-workspace")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.workspaceURL)
        let update = try fixture.connection.prepare("UPDATE workspaces SET folder_path = ? WHERE id = ?")
        try update.bind(alias.path, at: 1)
        try update.bind("main", at: 2)
        _ = try update.step()
        _ = try fixture.index()
        try update.reset()
        try update.bind(fixture.workspaceURL.path + "/", at: 1)
        try update.bind("other", at: 2)
        _ = try update.step()
        #expect(throws: SQLiteDatabaseError.self) { try fixture.index() }
        _ = try SQLiteNoteSearchIndex(databaseURL: fixture.databaseURL, workspaceURL: alias)
    }

    @Test func failedOrIncompatibleRecordsInvalidateUnchangedFilesystemMtime() async throws {
        let fixture = try SQLiteDesktopFixture()
        defer { fixture.cleanUp() }
        try fixture.seed(vector: fixture.vector())
        let index = try fixture.index()
        let note = try fixture.note()
        try await index.upsert(note)
        for mutation in ["status = 'failed'", "model = 'old-model'", "dimensions = 512", "chunk_count = 999"] {
            try fixture.connection.execute("UPDATE note_index_records SET \(mutation)")
            #expect(try await index.indexedFiles().first?.modifiedAt != note.modifiedAt)
            try await index.upsert(note)
            #expect(try await index.indexedFiles().first?.modifiedAt == note.modifiedAt)
            #expect(try fixture.scalar("SELECT title FROM notes") == "Desktop title")
            #expect(try await index.pendingEmbeddings(modelIdentifier: SQLiteDesktopFixture.model, limit: 5).count == 1)
        }
    }

    @Test func duplicateDesktopPathsProduceOneRefreshIdentity() async throws {
        let fixture = try SQLiteDesktopFixture()
        defer { fixture.cleanUp() }
        try fixture.seed(id: "older", vector: fixture.vector())
        try fixture.seed(id: "newer", vector: fixture.vector())
        let index = try fixture.index()
        #expect(try await index.indexedFiles().count == 1)
    }

    @Test func reusesExistingDesktopVectorsImmediatelyAndScopesWorkspace() async throws {
        let fixture = try SQLiteDesktopFixture()
        defer { fixture.cleanUp() }
        try fixture.seed(vector: fixture.vector())
        try fixture.seed(id: "elsewhere", path: "secret.md", workspace: "other", vector: fixture.vector())
        let index = try fixture.index()
        let hits = try await index.candidates(query: "unrelated", embedding: fixture.embedding(), limit: 10)
        #expect(hits.map(\.note.path.value) == ["note.md"])
        #expect(hits.first?.note.title == "Desktop title")
        #expect((hits.first?.semanticSimilarity ?? 0) > 0.999)
        #expect(try await index.candidates(query: "Apple", embedding: nil, limit: 10).map(\.note.path.value) == ["note.md"])
        #expect(try await index.pendingEmbeddings(modelIdentifier: SQLiteDesktopFixture.model, limit: 10).isEmpty)
    }

    @Test func unchangedRawSourcePreservesDesktopChunksVectorsAndMetadata() async throws {
        let fixture = try SQLiteDesktopFixture()
        defer { fixture.cleanUp() }
        try fixture.seed(vector: fixture.vector(0.3, 0.8))
        let beforeBlob = try fixture.scalar("SELECT hex(embedding) FROM note_chunks WHERE note_id = 'existing'")
        let index = try fixture.index()
        let note = try fixture.note()
        try await index.upsert(note)
        #expect(try fixture.scalar("SELECT id FROM note_chunks WHERE note_id = 'existing'") == "existing:0")
        #expect(try fixture.scalar("SELECT hex(embedding) FROM note_chunks WHERE note_id = 'existing'") == beforeBlob)
        #expect(try fixture.scalar("SELECT title FROM notes WHERE id = 'existing'") == "Desktop title")
        #expect(try fixture.scalar("SELECT updated_at FROM notes WHERE id = 'existing'") == "20")
        #expect(try await index.indexedFiles() == [NoteFileInfo(path: note.path, modifiedAt: note.modifiedAt)])
        let reopened = try fixture.index()
        #expect(try await reopened.indexedFiles() == [NoteFileInfo(path: note.path, modifiedAt: note.modifiedAt)])
        #expect(try await reopened.pendingEmbeddings(modelIdentifier: SQLiteDesktopFixture.model, limit: 10).isEmpty)
    }

    @Test func changingContentPreservesFlagsAndRelationsAndUpdatesDerivedTables() async throws {
        let fixture = try SQLiteDesktopFixture()
        defer { fixture.cleanUp() }
        try fixture.seed(vector: fixture.vector())
        let index = try fixture.index()
        let updated = try fixture.note(source: "# Pears\n\nHarvest yellow pears.", time: 99.375)
        try await index.upsert(updated)
        #expect(try fixture.scalar("SELECT count(*) FROM notes") == "1")
        #expect(try fixture.scalar("SELECT title FROM notes WHERE id = 'existing'") == "Pears")
        #expect(try fixture.scalar("SELECT updated_at FROM notes WHERE id = 'existing'") == "99")
        #expect(try fixture.scalar("SELECT created_at FROM notes WHERE id = 'existing'") == "10")
        #expect(try fixture.scalar("SELECT notebook_id FROM notes WHERE id = 'existing'") == "book")
        #expect(try fixture.scalar("SELECT is_favorite + is_pinned + is_archived FROM notes WHERE id = 'existing'") == "3")
        #expect(try fixture.scalar("SELECT count(*) FROM note_tags") == "1")
        #expect(try fixture.scalar("SELECT count(*) FROM note_topics") == "1")
        #expect(try fixture.scalar("SELECT content_hash FROM note_index_records WHERE note_id = 'existing'") == NoteContentHasher.hash(updated.source))
        #expect(try fixture.scalar("SELECT status FROM note_index_records WHERE note_id = 'existing'") == "pending")
        #expect(try await index.candidates(query: "Apple", embedding: nil, limit: 5).isEmpty)
        #expect(try await index.candidates(query: "pears", embedding: nil, limit: 5).count == 1)
        #expect(try await index.pendingEmbeddings(modelIdentifier: SQLiteDesktopFixture.model, limit: 5).count == 1)
    }

    @Test func newlyCapturedNoteUsesDesktopRowsAndFloat32Embeddings() async throws {
        let fixture = try SQLiteDesktopFixture()
        defer { fixture.cleanUp() }
        let index = try fixture.index()
        let note = try fixture.note("Journal/2026-10-11.md", source: "# 2026-10-11\n\n[11:30] Write a local search test.")
        try await index.upsert(note)
        let id = try fixture.scalar("SELECT id FROM notes")
        #expect(UUID(uuidString: id) != nil)
        #expect(try fixture.scalar("SELECT workspace_id FROM notes") == "main")
        #expect(try fixture.scalar("SELECT is_favorite + is_pinned + is_archived + is_deleted FROM notes") == "0")
        let input = try #require(try await index.pendingEmbeddings(modelIdentifier: SQLiteDesktopFixture.model, limit: 5).first)
        #expect(input.key != nil)
        try await index.storeEmbedding(fixture.embedding(0.25, 0.75), for: input)
        #expect(try fixture.scalar("SELECT length(embedding) FROM note_chunks") == "1536")
        #expect(try fixture.scalar("SELECT hex(substr(embedding, 1, 8)) FROM note_chunks") == "0000803E0000403F")
        #expect(try fixture.scalar("SELECT status FROM note_index_records") == "indexed")
        #expect(try fixture.scalar("SELECT model FROM note_index_records") == SQLiteDesktopFixture.model)
        #expect(try await index.candidates(query: "search", embedding: fixture.embedding(0.25, 0.75), limit: 5).first?.note.isJournal == true)
    }

    @Test func missingFilesRemoveOnlyDerivedIndexAndLeaveOtherWorkspacesUntouched() async throws {
        let fixture = try SQLiteDesktopFixture()
        defer { fixture.cleanUp() }
        try fixture.seed(vector: fixture.vector())
        try fixture.seed(id: "elsewhere", workspace: "other", vector: fixture.vector())
        let index = try fixture.index()
        try await index.upsert(fixture.note())
        try await index.remove([try NotePath("note.md")])
        for table in ["note_chunks", "note_chunks_fts", "note_index_records", "stone_swift_index_state"] {
            #expect(try fixture.scalar("SELECT count(*) FROM \(table) WHERE workspace_id = 'main'") == "0")
        }
        #expect(try fixture.scalar("SELECT count(*) FROM notes") == "2")
        #expect(try fixture.scalar("SELECT count(*) FROM note_tags") == "2")
        #expect(try fixture.scalar("SELECT count(*) FROM note_topics") == "2")
        #expect(try fixture.scalar("SELECT count(*) FROM note_chunks WHERE workspace_id = 'other'") == "1")
        #expect(try fixture.scalar("SELECT is_deleted FROM notes WHERE id = 'existing'") == "0")
        #expect(try await index.candidates(query: "Desktop", embedding: fixture.embedding(), limit: 5).isEmpty)
    }

    @Test func softDeletedNotesAreNeverResurrectedEvenWithAnActiveDuplicate() async throws {
        let fixture = try SQLiteDesktopFixture()
        defer { fixture.cleanUp() }
        try fixture.seed(id: "trashed", deleted: true, vector: fixture.vector())
        try fixture.seed(id: "active-duplicate", vector: fixture.vector())
        let index = try fixture.index()
        try await index.upsert(fixture.note(source: "# Changed\n\nMust not import this content."))
        #expect(try fixture.scalar("SELECT count(*) FROM notes") == "2")
        #expect(try fixture.scalar("SELECT title FROM notes WHERE id = 'trashed'") == "Desktop title")
        #expect(try fixture.scalar("SELECT is_deleted FROM notes WHERE id = 'trashed'") == "1")
        #expect(try fixture.scalar("SELECT count(*) FROM stone_swift_index_state") == "0")
        #expect(try await index.candidates(query: "Changed", embedding: nil, limit: 5).isEmpty)
        try fixture.connection.execute("UPDATE notes SET is_deleted = 1")
        #expect(try await index.candidates(query: "Apple", embedding: fixture.embedding(), limit: 5).isEmpty)
        #expect(try await index.pendingEmbeddings(modelIdentifier: SQLiteDesktopFixture.model, limit: 5).isEmpty)
    }

    @Test func lateEmbeddingCannotAttachWhenSQLiteReusesAChunkRowID() async throws {
        let fixture = try SQLiteDesktopFixture()
        defer { fixture.cleanUp() }
        let index = try fixture.index()
        let note = try fixture.note()
        try await index.upsert(note)
        let original = try #require(try await index.pendingEmbeddings(modelIdentifier: SQLiteDesktopFixture.model, limit: 1).first)
        try await index.remove([note.path])
        try await index.upsert(note)
        let replacement = try #require(try await index.pendingEmbeddings(modelIdentifier: SQLiteDesktopFixture.model, limit: 1).first)
        #expect(original.id == replacement.id)
        #expect(original.key != replacement.key)
        #expect(original.text == replacement.text)
        try await index.storeEmbedding(fixture.embedding(), for: original)
        #expect(try await index.pendingEmbeddings(modelIdentifier: SQLiteDesktopFixture.model, limit: 5) == [replacement])
        try await index.storeEmbedding(fixture.embedding(), for: NoteEmbeddingInput(id: replacement.id, text: "wrong", key: replacement.key))
        #expect(try await index.pendingEmbeddings(modelIdentifier: SQLiteDesktopFixture.model, limit: 5) == [replacement])
    }

    @Test func modelMismatchAndMalformedVectorsDoNotEnterSemanticResults() async throws {
        let fixture = try SQLiteDesktopFixture()
        defer { fixture.cleanUp() }
        try fixture.seed(vector: fixture.vector(), model: "different-model")
        let index = try fixture.index()
        #expect(try await index.candidates(query: "unrelated", embedding: fixture.embedding(), limit: 5).isEmpty)
        #expect(try await index.candidates(query: "apple", embedding: fixture.embedding(), limit: 5).count == 1)
        try await index.upsert(fixture.note())
        #expect(try fixture.scalar("SELECT title FROM notes") == "Desktop title")
        let input = try #require(try await index.pendingEmbeddings(modelIdentifier: SQLiteDesktopFixture.model, limit: 1).first)
        for embedding in [TextEmbedding(modelIdentifier: "wrong", vector: fixture.vector()),
                          TextEmbedding(modelIdentifier: SQLiteDesktopFixture.model, vector: [1, 0]),
                          fixture.embedding(.nan, 1), fixture.embedding(0, 0)] {
            await #expect(throws: SQLiteDatabaseError.self) { try await index.storeEmbedding(embedding, for: input) }
        }
        try await index.storeEmbedding(fixture.embedding(), for: input)
        try fixture.connection.execute("UPDATE note_chunks SET embedding = zeroblob(1536)")
        #expect(try await index.candidates(query: "unrelated", embedding: fixture.embedding(), limit: 5).isEmpty)
        try fixture.connection.execute("UPDATE note_chunks SET embedding = X'00'")
        #expect(try await index.pendingEmbeddings(modelIdentifier: SQLiteDesktopFixture.model, limit: 5).count == 1)
        #expect(try await index.candidates(query: "unrelated", embedding: fixture.embedding(), limit: 5).isEmpty)
    }

    @Test func chunkAndFTSUpdatesRollBackTogetherOnFailure() async throws {
        let fixture = try SQLiteDesktopFixture()
        defer { fixture.cleanUp() }
        try fixture.seed(vector: fixture.vector())
        let index = try fixture.index()
        try fixture.connection.execute("""
            CREATE TRIGGER reject_chunk BEFORE INSERT ON note_chunks BEGIN
                SELECT RAISE(ABORT, 'test write failure');
            END
            """)
        await #expect(throws: SQLiteDatabaseError.self) {
            try await index.upsert(fixture.note(source: "# Replacement\n\nChanged text."))
        }
        #expect(try fixture.scalar("SELECT title FROM notes") == "Desktop title")
        #expect(try fixture.scalar("SELECT id FROM note_chunks") == "existing:0")
        #expect(try fixture.scalar("SELECT chunk_id FROM note_chunks_fts") == "existing:0")
        #expect(try await index.candidates(query: "Apple", embedding: nil, limit: 5).count == 1)
        #expect(try await index.candidates(query: "Replacement", embedding: nil, limit: 5).isEmpty)
        try fixture.connection.execute("INSERT INTO note_chunks_fts(note_chunks_fts) VALUES ('integrity-check')")
    }

    @Test func startupNeverCreatesDatabaseOrRunsDesktopMigrations() throws {
        let fixture = try SQLiteDesktopFixture()
        defer { fixture.cleanUp() }
        let missing = fixture.root.appendingPathComponent("missing/stone.db")
        #expect(throws: SQLiteDatabaseError.self) { try SQLiteNoteSearchIndex(databaseURL: missing, workspaceURL: fixture.workspaceURL) }
        #expect(!FileManager.default.fileExists(atPath: missing.deletingLastPathComponent().path))
        let before = Set(try fixture.rows("SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'").compactMap(\.first))
        _ = try fixture.index()
        let after = Set(try fixture.rows("SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'").compactMap(\.first))
        #expect(after.subtracting(before) == ["stone_swift_index_state"])
        #expect(try fixture.scalar("PRAGMA user_version") == "73")
        #expect(try fixture.scalar("SELECT hash FROM __drizzle_migrations") == "desktop-migration")
    }

    @Test func incompatibleSchemaAndUnregisteredWorkspaceLeaveDatabaseUntouched() throws {
        let fixture = try SQLiteDesktopFixture()
        defer { fixture.cleanUp() }
        #expect(throws: SQLiteDatabaseError.self) {
            try SQLiteNoteSearchIndex(databaseURL: fixture.databaseURL, workspaceURL: fixture.root.appendingPathComponent("unknown"))
        }
        #expect(try fixture.scalar("SELECT count(*) FROM sqlite_master WHERE name = 'stone_swift_index_state'") == "0")
        try fixture.connection.execute("DROP TABLE note_chunks_fts")
        #expect(throws: SQLiteDatabaseError.self) { try fixture.index() }
        #expect(try fixture.scalar("SELECT count(*) FROM sqlite_master WHERE name = 'stone_swift_index_state'") == "0")
        #expect(try fixture.scalar("SELECT count(*) FROM workspaces") == "2")
    }

    @Test func lexicalAndSemanticUnionSupportsPrefixesAndRejectsFTSSyntax() async throws {
        let fixture = try SQLiteDesktopFixture()
        defer { fixture.cleanUp() }
        try fixture.seed(id: "lexical", path: "lexical.md", source: "# Café\n\nSolar panel instructions", vector: fixture.vector(0, 1))
        try fixture.seed(id: "semantic", path: "semantic.md", source: "# Renewable\n\nSunlight becomes electricity", vector: fixture.vector())
        let index = try fixture.index()
        let hits = try await index.candidates(query: "solar pan", embedding: fixture.embedding(), limit: 2)
        #expect(Set(hits.map(\.note.path.value)) == ["lexical.md", "semantic.md"])
        #expect(hits.first(where: { $0.note.path.value == "lexical.md" })?.text.contains("Solar panel") == true)
        #expect(try await index.candidates(query: "cafe", embedding: nil, limit: 5).count == 1)
        for query in ["", "!!! : \" * ( )", "\" OR 1=1 --", "'; DROP TABLE notes; --"] {
            #expect(try await index.candidates(query: query, embedding: nil, limit: 5).isEmpty)
        }
        #expect(try await index.candidates(query: "solar", embedding: nil, limit: 0).isEmpty)
        #expect(try await index.candidates(query: "solar", embedding: nil, limit: -1).isEmpty)
    }

    @Test func cursorSkipsUnembeddableChunksAndHeadingOnlyNotesRemainSearchable() async throws {
        let fixture = try SQLiteDesktopFixture()
        defer { fixture.cleanUp() }
        let index = try fixture.index()
        try await index.upsert(fixture.note("one.md", source: "# First\n\nFirst body."))
        try await index.upsert(fixture.note("two.md", source: "# Second\n\nSecond body."))
        try await index.upsert(fixture.note("empty.md", source: "# Uniqueheading"))
        let first = try #require(try await index.pendingEmbeddings(modelIdentifier: SQLiteDesktopFixture.model, afterID: nil, limit: 1).first)
        let next = try #require(try await index.pendingEmbeddings(modelIdentifier: SQLiteDesktopFixture.model, afterID: first.id, limit: 1).first)
        #expect(next.id > first.id)
        #expect(try await index.pendingEmbeddings(modelIdentifier: SQLiteDesktopFixture.model, afterID: next.id, limit: 1).isEmpty)
        #expect(try await index.candidates(query: "Uniqueheading", embedding: nil, limit: 5).map(\.note.path.value) == ["empty.md"])
    }
}
