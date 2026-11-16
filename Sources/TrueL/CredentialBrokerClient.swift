import Foundation
import Security
import CredentialCore

@MainActor
final class CredentialBrokerClient {
    private let requirement: String?
    init(bundle: Bundle = .main) {
        requirement = bundle.object(forInfoDictionaryKey: "TrueLCredentialBrokerRequirement") as? String
    }

    func read(account: String, allowInteraction: Bool) async throws -> String? {
        guard CredentialContract.accounts.contains(account) else { throw CredentialStoreError(status: errSecParam) }
        return try await call(timeout: allowInteraction ? 120 : 15) { proxy, finish in
            proxy.readKey(for: account, allowInteraction: allowInteraction) { key, status in
                if status != 0 { finish(.failure(CredentialStoreError(status: status))) }
                else if let key, !CredentialContract.validKey(key) { finish(.failure(CredentialStoreError(status: errSecDecode))) }
                else { finish(.success(key)) }
            }
        }
    }

    func save(_ key: String, account: String) async throws {
        guard CredentialContract.accounts.contains(account), CredentialContract.validKey(key) else {
            throw CredentialStoreError(status: errSecParam)
        }
        let _: Bool = try await call(timeout: 120) { proxy, finish in
            proxy.saveKey(key, for: account) { status in
                finish(status == 0 ? .success(true) : .failure(CredentialStoreError(status: status)))
            }
        }
    }

    func checkStorage(ticket: String, operation: String) async throws {
        guard UUID(uuidString: ticket) != nil, ["create", "read", "delete"].contains(operation) else {
            throw CredentialStoreError(status: errSecParam)
        }
        let _: Bool = try await call(timeout: 15) { proxy, finish in
            proxy.checkStorage(ticket, operation: operation) { success, status in
                finish(success && status == 0 ? .success(true) : .failure(CredentialStoreError(status: status)))
            }
        }
    }

    private func call<Value: Sendable>(timeout: TimeInterval,
        _ invoke: (any CredentialBrokerProtocol, @escaping @Sendable (Result<Value, any Error>) -> Void) -> Void
    ) async throws -> Value {
        guard let requirement else { throw CredentialStoreError(status: -10001) }
        var parsed: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &parsed) == errSecSuccess else {
            throw CredentialStoreError(status: -10001)
        }
        let connection = NSXPCConnection(serviceName: CredentialContract.serviceID)
        connection.setCodeSigningRequirement(requirement)
        connection.remoteObjectInterface = NSXPCInterface(with: CredentialBrokerProtocol.self)
        let pending = BrokerReply<Value>(connection: connection)
        connection.interruptionHandler = { @Sendable in pending.finish(.failure(CredentialStoreError(status: -10002))) }
        connection.invalidationHandler = { @Sendable in pending.finish(.failure(CredentialStoreError(status: -10002))) }
        // Activate before installing cancellation: an already-cancelled task
        // must never invalidate a suspended connection and then resume it.
        connection.resume()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.install(continuation)
                pending.scheduleTimeout(after: timeout)
                guard !Task.isCancelled else { pending.finish(.failure(CancellationError())); return }
                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ @Sendable _ in
                    pending.finish(.failure(CredentialStoreError(status: -10002)))
                }) as? any CredentialBrokerProtocol else {
                    pending.finish(.failure(CredentialStoreError(status: -10002))); return
                }
                invoke(proxy) { pending.finish($0) }
            }
        } onCancel: { pending.finish(.failure(CancellationError())) }
    }
}

/// Reply, interruption, cancellation and timeout can race on different XPC
/// queues. Resume exactly once and release the connection on every path.
final class BrokerReply<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: NSXPCConnection
    private var continuation: CheckedContinuation<Value, any Error>?
    private var earlyResult: Result<Value, any Error>?
    private var finished = false
    private var timeout: DispatchWorkItem?

    init(connection: NSXPCConnection) { self.connection = connection }
    func install(_ value: CheckedContinuation<Value, any Error>) {
        lock.lock()
        let early = earlyResult
        earlyResult = nil
        if !finished { continuation = value }
        lock.unlock()
        if let early { value.resume(with: early) }
    }
    func scheduleTimeout(after seconds: TimeInterval) {
        let item = DispatchWorkItem { [weak self] in self?.finish(.failure(CredentialStoreError(status: -10003))) }
        lock.lock()
        if finished { lock.unlock(); return }
        timeout = item
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: item)
    }
    func finish(_ result: Result<Value, any Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let reply = continuation
        continuation = nil
        if reply == nil { earlyResult = result }
        timeout?.cancel()
        timeout = nil
        lock.unlock()
        connection.interruptionHandler = nil
        connection.invalidationHandler = nil
        connection.invalidate()
        reply?.resume(with: result)
    }
}
