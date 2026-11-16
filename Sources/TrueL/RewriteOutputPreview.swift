import Foundation

enum RewriteOutputPreview {
    /// The prompt requests output first. If a provider reorders fields, defer to
    /// final decoding instead of accidentally showing an output nested in metadata.
    static func completedText(in partialJSON: String) -> String? {
        var text = partialJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            guard let newline = text.firstIndex(of: "\n") else { return nil }
            text = String(text[text.index(after: newline)...])
        }
        let bytes = Array(text.utf8)
        var cursor = 0
        func consume(_ token: String) -> Bool {
            while cursor < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[cursor]) { cursor += 1 }
            guard bytes.dropFirst(cursor).starts(with: token.utf8) else { return false }
            cursor += token.utf8.count
            return true
        }
        guard consume("{"), consume("\"output\""), consume(":"), consume("\"") else { return nil }
        let openingQuote = cursor - 1
        var escaped = false
        for index in cursor..<bytes.count {
            let byte = bytes[index]
            if escaped { escaped = false }
            else if byte == 0x5C { escaped = true }
            else if byte == 0x22 {
                // Foundation handles all JSON escapes and Unicode surrogate pairs.
                guard let output = try? JSONDecoder().decode(String.self, from: Data(bytes[openingQuote...index])),
                      !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return output
            }
        }
        return nil
    }
}
