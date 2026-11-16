import AppKit
import Foundation
import CredentialCore

@main
struct CredentialProbe {
    @MainActor static func main() async {
        _ = NSApplication.shared
        let args = CommandLine.arguments
        guard args.count == 3 else { exit(64) }
        #if PROBE_BUILD_2
        print("probe-build=2")
        #elseif PROBE_BUILD_3
        print("probe-build=3")
        #else
        print("probe-build=1")
        #endif
        do {
            try await CredentialBrokerClient().checkStorage(ticket: args[2], operation: args[1])
            print("PASS credential \(args[1]) without interaction")
            exit(0)
        } catch {
            print("FAIL credential status=\((error as? CredentialStoreError)?.status ?? -1)")
            exit(1)
        }
    }
}
