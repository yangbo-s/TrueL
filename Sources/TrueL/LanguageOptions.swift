import Foundation
import NaturalLanguage

enum TextLanguage: String, CaseIterable, Sendable {
    case simplifiedChinese = "简体中文", traditionalChinese = "繁體中文"
    case english = "English", japanese = "日本語", korean = "한국어"
    case french = "Français", german = "Deutsch", spanish = "Español"

    static let automatic = "检测语言"
    var alternate: TextLanguage {
        self == .simplifiedChinese || self == .traditionalChinese ? .english : .simplifiedChinese
    }

    static func detect(_ text: String) -> TextLanguage? {
        let sample = String(text.prefix(2_000)).trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCJK = sample.unicodeScalars.contains {
            (0x4E00...0x9FFF).contains($0.value) || (0x3040...0x30FF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value)
        }
        guard hasCJK || sample.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 3 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 4)
        guard let (language, confidence) = hypotheses.max(by: { $0.value < $1.value }) else { return nil }
        // Shared Han characters split probability between the two Chinese variants.
        // Choose the script from actual characters instead of guessing traditional
        // for short phrases such as 你好, which would look like same-language output.
        let chineseConfidence = (hypotheses[.simplifiedChinese] ?? 0) + (hypotheses[.traditionalChinese] ?? 0)
        if chineseConfidence >= 0.6 && chineseConfidence >= confidence {
            let simplified = sample.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false)
            return simplified != nil && simplified != sample ? .traditionalChinese : .simplifiedChinese
        }
        guard confidence >= 0.6 else { return nil }
        switch language {
        case .simplifiedChinese: return .simplifiedChinese
        case .traditionalChinese: return .traditionalChinese
        case .english: return .english
        case .japanese: return .japanese
        case .korean: return .korean
        case .french: return .french
        case .german: return .german
        case .spanish: return .spanish
        default: return nil
        }
    }
}

struct TextStyle: Sendable {
    let id: String
    let title: String
    let instruction: String

    static let translation: [TextStyle] = [
        .init(id: "standard", title: "自然", instruction: "Use natural, idiomatic wording while preserving all information and the original tone."),
        .init(id: "literal", title: "直译", instruction: "Stay close to the source wording and structure while keeping the translation grammatical."),
        .init(id: "professional", title: "正式", instruction: "Use polished, formal language suitable for professional communication. Preserve all factual details."),
        .init(id: "concise", title: "简洁", instruction: "Use concise wording without dropping facts, qualifications, names or numbers.")
    ]
    static let grammar: [TextStyle] = [
        .init(id: "standard", title: "标准", instruction: "Correct grammar and awkward phrasing with minimal changes; preserve the author's voice."),
        .init(id: "professional", title: "专业", instruction: "Use polished, professional wording while preserving meaning and all factual details."),
        .init(id: "social", title: "轻松", instruction: "Use a friendly, conversational tone without adding facts, slang or emojis that are absent from the source."),
        .init(id: "concise", title: "简洁", instruction: "Remove redundancy and simplify phrasing without losing meaning or factual details.")
    ]
    static func choices(for mode: WorkMode) -> [TextStyle] { mode == .translation ? translation : grammar }
    static func resolve(_ id: String, for mode: WorkMode) -> TextStyle {
        choices(for: mode).first { $0.id == id } ?? choices(for: mode)[0]
    }
}
