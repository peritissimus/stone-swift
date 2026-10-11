/// Stone desktop's FNV-1a fingerprint of the exact UTF-8 Markdown or chunk text.
public enum NoteContentHasher {
    public static func hash(_ source: String) -> String {
        guard !source.isEmpty else { return "0000000000000000" }
        var value: UInt64 = 0xcbf29ce484222325
        for byte in source.utf8 { value = (value ^ UInt64(byte)) &* 0x100000001b3 }
        let hex = String(value, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}
