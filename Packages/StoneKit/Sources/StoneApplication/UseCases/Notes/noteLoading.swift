import StoneDomain

/// Reads one note into an entity, mapping a missing file to the domain's `notFound`.
func loadNote(
    _ path: NotePath, from repository: any INoteRepository, policy: LocationPolicy
) async throws -> NoteEntity {
    guard let info = try await repository.info(path) else { throw NoteError.notFound(path) }
    let source = try await repository.read(path)
    return NoteEntity(path: path, source: source, modifiedAt: info.modifiedAt, policy: policy)
}

/// Reads every note concurrently, newest first; a file that vanishes mid-read is skipped.
func loadAllNotes(from repository: any INoteRepository, policy: LocationPolicy) async throws -> [NoteEntity] {
    let files = try await repository.listNotes()
    let notes = await withTaskGroup(of: NoteEntity?.self) { group in
        for file in files {
            group.addTask {
                guard let source = try? await repository.read(file.path) else { return nil }
                return NoteEntity(path: file.path, source: source, modifiedAt: file.modifiedAt, policy: policy)
            }
        }
        var loaded: [NoteEntity] = []
        for await note in group { if let note { loaded.append(note) } }
        return loaded
    }
    return notes.sorted(by: newestFirst)
}

func newestFirst(_ lhs: NoteEntity, _ rhs: NoteEntity) -> Bool {
    lhs.modifiedAt != rhs.modifiedAt ? lhs.modifiedAt > rhs.modifiedAt : lhs.path < rhs.path
}
