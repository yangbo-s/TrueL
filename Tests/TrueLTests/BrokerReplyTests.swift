import Foundation
import Testing
@testable import TrueL

struct BrokerReplyTests {
    @Test func replyBeforeContinuationIsInstalledIsNotLost() async throws {
        let pending = BrokerReply<String>(connection: NSXPCConnection(serviceName: "com.truel.test.unused"))
        pending.finish(.success("fixture"))
        let value = try await withCheckedThrowingContinuation { pending.install($0) }
        #expect(value == "fixture")
    }

    @Test func racingReplyAndInvalidationResumeExactlyOnce() async throws {
        for _ in 0..<50 {
            let pending = BrokerReply<Int>(connection: NSXPCConnection(serviceName: "com.truel.test.unused"))
            let value = try await withCheckedThrowingContinuation { continuation in
                pending.install(continuation)
                DispatchQueue.global().async { pending.finish(.success(1)) }
                DispatchQueue.global().async { pending.finish(.success(2)) }
            }
            #expect([1, 2].contains(value))
        }
    }

    @Test func missingReplyTimesOutAndLateSuccessCannotResumeAgain() async {
        let pending = BrokerReply<Bool>(connection: NSXPCConnection(serviceName: "com.truel.test.unused"))
        do {
            _ = try await withCheckedThrowingContinuation { continuation in
                pending.install(continuation)
                pending.scheduleTimeout(after: 0.01)
            }
            Issue.record("A missing response must not succeed")
        } catch {
            #expect((error as? CredentialStoreError)?.status == -10003)
        }
        pending.finish(.success(true))
    }
}
