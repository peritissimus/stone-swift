/// Produces local, model-specific vectors. An unavailable model may return nil.
public protocol ITextEmbedder: Sendable {
    var modelIdentifier: String { get }
    func embed(_ text: String) async throws -> TextEmbedding?
}
