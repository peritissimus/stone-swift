/// Scores query/text pairs with the same cross-encoder used by Stone desktop.
public protocol ITextReranker: Sendable {
    func rerank(query: String, texts: [String]) async throws -> [Double]
}
