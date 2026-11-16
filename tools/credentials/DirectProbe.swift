import Foundation
import Security

// Reproduces the original bug without touching production service/account IDs.
#if PROBE_BUILD_2
print("direct-build=2")
#else
print("direct-build=1")
#endif
let action = CommandLine.arguments[1]
let ticket = CommandLine.arguments[2]
guard UUID(uuidString: ticket) != nil, ["create", "read", "delete"].contains(action) else { exit(64) }
SecKeychainSetUserInteractionAllowed(false)
let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.truel.credential-regression", kSecAttrAccount as String: ticket]
var status: OSStatus
switch action {
case "create":
    var item = query
    item[kSecValueData as String] = Data(ticket.utf8)
    status = SecItemAdd(item as CFDictionary, nil)
case "delete": status = SecItemDelete(query as CFDictionary)
default:
    var item = query
    item[kSecReturnData as String] = true
    item[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    status = SecItemCopyMatching(item as CFDictionary, &result)
    if status == 0, (result as? Data) != Data(ticket.utf8) { status = errSecDecode }
}
print("direct \(action) status=\(status)")
exit(status == 0 ? 0 : 1)
