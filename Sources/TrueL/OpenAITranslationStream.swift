import Foundation

enum AIStreamEvent: Sendable {
    case response(HTTPURLResponse)
    case line(String)
}

/// OpenAI emits one JSON chunk per SSE data line. Keep transport state off the
/// main actor and publish only visible text, with the first chunk sent immediately.
actor OpenAITranslationStream {
    private let onUpdate: TranslationTextUpdate
    private var receivedResponse = false
    private var receivedStop = false
    private var receivedDone = false
    private var byteCount = 0
    private var text = ""
    private var lastUpdate: ContinuousClock.Instant?

    init(onUpdate: @escaping TranslationTextUpdate) { self.onUpdate = onUpdate }

    func receive(_ event: AIStreamEvent) async throws {
        try Task.checkCancellation()
        switch event {
        case .response(let response):
            guard !receivedResponse else { throw AIClientError.invalidResponse }
            try AIClient.validateStatus(response)
            guard response.mimeType?.lowercased() == "text/event-stream" else { throw AIClientError.invalidResponse }
            receivedResponse = true
        case .line(let line):
            guard receivedResponse else { throw AIClientError.invalidResponse }
            byteCount += line.utf8.count + 1
            guard byteCount <= 10_000_000 else { throw AIClientError.invalidResponse }
            guard line.hasPrefix("data:") else { return }
            let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !receivedDone else { throw AIClientError.invalidResponse }
            if data == "[DONE]" {
                guard receivedStop else { throw AIClientError.invalidResponse }
                receivedDone = true
                return
            }
            guard let object = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
                  object["error"] == nil,
                  let choices = object["choices"] as? [[String: Any]] else { throw AIClientError.invalidResponse }
            // Empty choices are valid for usage-only chunks.
            guard let choice = choices.first else { return }
            guard !receivedStop, choice["index"] as? Int == 0,
                  let delta = choice["delta"] as? [String: Any] else { throw AIClientError.invalidResponse }
            if let refusal = delta["refusal"] as? String, !refusal.isEmpty { throw AIClientError.blocked }
            if let reason = choice["finish_reason"] as? String {
                switch reason {
                case "stop": receivedStop = true
                case "length": throw AIClientError.truncated
                case "content_filter": throw AIClientError.blocked
                default: throw AIClientError.invalidResponse
                }
            }
            if let content = delta["content"] as? String, !content.isEmpty {
                text += content
                let now = ContinuousClock.now
                if lastUpdate.map({ now - $0 >= .milliseconds(32) }) ?? true {
                    try await onUpdate(text)
                    lastUpdate = now
                }
            }
        }
    }

    func finish() throws -> String {
        try Task.checkCancellation()
        guard receivedResponse, receivedStop, receivedDone else { throw AIClientError.invalidResponse }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw AIClientError.emptyResponse }
        return result
    }
}
