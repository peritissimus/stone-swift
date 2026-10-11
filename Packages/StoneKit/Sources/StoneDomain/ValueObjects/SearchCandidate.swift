public struct SearchCandidate: Hashable, Sendable {
    public let note: NoteSummary
    public let text: String
    public let lexicalRank: Int?
    public let semanticSimilarity: Double?

    public init(note: NoteSummary, text: String, lexicalRank: Int?, semanticSimilarity: Double?) {
        self.note = note
        self.text = text
        self.lexicalRank = lexicalRank
        self.semanticSimilarity = semanticSimilarity
    }
}
