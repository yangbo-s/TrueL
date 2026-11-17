import Foundation

/// Removes only the request envelope accidentally echoed around prose translations.
struct TranslationOutput: Sendable {
    let preservesStructure: Bool

    init(source: String) {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        preservesStructure = text.hasPrefix("{") || text.hasPrefix("[") || text.hasPrefix("```")
    }

    func preview(_ raw: String) -> String? {
        guard !preservesStructure else { return raw }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // The first delta can be just `{` or one backtick. Wait for the full
        // response rather than expose JSON syntax or incomplete string escapes.
        guard !text.isEmpty, !text.hasPrefix("{"), !text.hasPrefix("```"), !"```".hasPrefix(text) else { return nil }
        return raw
    }

    func finalText(_ raw: String) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preservesStructure else { return text }
        var candidate = text
        var unclosedFence = false
        if let newline = text.firstIndex(of: "\n"),
           ["```", "```json"].contains(text[..<newline].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            let body = String(text[text.index(after: newline)...])
            unclosedFence = !body.hasSuffix("```")
            candidate = (unclosedFence ? body : String(body.dropLast(3))).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard candidate.range(of: #"^\{\s*"source"\s*:"#, options: .regularExpression) != nil else { return text }
        guard !unclosedFence,
              (try? JSONSerialization.jsonObject(with: Data(candidate.utf8))) != nil else {
            throw LanguageResponseError.invalidTranslation
        }
        // Match one literal key and one string only. Decoding into a dictionary
        // first would silently collapse duplicate keys and could discard content.
        guard let match = candidate.wholeMatch(of: #/\{\s*"source"\s*:\s*("(?:[^"\\]|\\.)*")\s*\}/#),
              let content = try? JSONDecoder().decode(String.self, from: Data(match.1.utf8)) else { return text }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
