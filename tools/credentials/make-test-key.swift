import Foundation
import CryptoKit

// Disposable update-signing key. Never reads the publisher's private key.
let key = Curve25519.Signing.PrivateKey()
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let exported = key.rawRepresentation.base64EncodedString()
try Data(exported.utf8).write(to: output, options: .atomic)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
print(key.publicKey.rawRepresentation.base64EncodedString())
