public struct NoteEmbeddingInput: Hashable, Sendable {
    public let id: Int64
    public let text: String
    public let key: String?

    public init(id: Int64, text: String, key: String? = nil) {
        self.id = id
        self.text = text
        self.key = key
    }
}
