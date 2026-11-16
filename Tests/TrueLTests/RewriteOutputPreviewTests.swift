import Foundation
import Testing
@testable import TrueL

struct RewriteOutputPreviewTests {
    @Test(arguments: ["Plain text.", "A \"quoted\" line.\nNext\tline\\tail", "中文 🌍 e\u{0301}",
                       "Braces } and text: \"output\": \"fake\"", "\\", "\"\u{0301}"])
    func onlyACompleteJSONStringBecomesVisible(_ output: String) throws {
        let encoded = String(decoding: try JSONEncoder().encode(output), as: UTF8.self)
        let prefix = "{ \n\"output\" \t: "
        for end in encoded.indices {
            #expect(RewriteOutputPreview.completedText(in: prefix + encoded[..<end]) == nil)
        }
        #expect(RewriteOutputPreview.completedText(in: prefix + encoded + ",\"corrections\":[") == output)
    }

    @Test func unicodeSurrogatesAndFencedResponsesUseStandardDecoding() {
        let raw = #"{"output":"\u4f60\u597d \ud83d\ude00\nnext","corrections":["#
        #expect(RewriteOutputPreview.completedText(in: raw) == "你好 😀\nnext")
        #expect(RewriteOutputPreview.completedText(in: "```json\n" + raw) == "你好 😀\nnext")
    }

    @Test(arguments: ["", "```json", #"{"output":"unfinished"#, #"{"output":"dangling\"#,
                       #"{"output":"bad\q"}"#, #"{"output":"\ud83d"}"#, #"{"output":"\u123"}"#,
                       #"{"output":null}"#, #"{"output":42}"#, #"{"output":"  \n "}"#,
                       #"{"corrections":[{"output":"nested trap"}],"output":"real"}"#,
                       #"{"not_output":"wrong"}"#, #"[{"output":"wrong"}]"#])
    func malformedOrNestedFieldsNeverLeakIntoThePreview(_ raw: String) {
        #expect(RewriteOutputPreview.completedText(in: raw) == nil)
    }
}
