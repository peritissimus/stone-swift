public struct DesktopNoteChunk: Hashable, Sendable {
    public let text: String
    public let headingPath: [String]
    public var tokenCount: Int { (text.utf16.count + 3) / 4 }

    public init(text: String, headingPath: [String]) {
        self.text = text
        self.headingPath = headingPath
    }
}
