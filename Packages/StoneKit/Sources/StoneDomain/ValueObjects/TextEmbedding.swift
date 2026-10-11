public struct TextEmbedding: Hashable, Sendable {
    public let modelIdentifier: String
    public let vector: [Double]

    public init(modelIdentifier: String, vector: [Double]) {
        self.modelIdentifier = modelIdentifier
        self.vector = vector
    }
}
