import CryptoKit
import Foundation

// Public-key verification only; this tool never reads the signing keychain.
guard (3...4).contains(CommandLine.arguments.count),
      let keyData = Data(base64Encoded: CommandLine.arguments[1]) else {
    fputs("Usage: verify-update PUBLIC_ED_KEY FILE [ARCHIVE_ED_SIGNATURE]\n", stderr)
    exit(2)
}
do {
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    let signed: Data
    let signature: Data
    if CommandLine.arguments.count == 4 {
        signed = bytes
        guard let decoded = Data(base64Encoded: CommandLine.arguments[3]) else { exit(2) }
        signature = decoded
    } else {
        // Sparkle 2.10 writes the signature block after the exact signed XML bytes.
        let marker = Data("<!-- sparkle-signatures:\n".utf8)
        guard let range = bytes.range(of: marker, options: .backwards),
              let block = String(data: bytes[range.lowerBound...], encoding: .utf8) else {
            fputs("FAIL unsigned feed\n", stderr); exit(1)
        }
        let lines = block.components(separatedBy: "\n")
        guard lines.count == 5, lines[1].hasPrefix("edSignature: "), lines[2].hasPrefix("length: "),
              lines[3] == "-->", lines[4].isEmpty,
              let length = Int(lines[2].dropFirst("length: ".count)), length == range.lowerBound,
              let decoded = Data(base64Encoded: String(lines[1].dropFirst("edSignature: ".count))) else {
            fputs("FAIL malformed feed signature\n", stderr); exit(1)
        }
        signed = bytes.prefix(length)
        signature = decoded
    }
    guard key.isValidSignature(signature, for: signed) else {
        fputs("FAIL invalid update signature\n", stderr); exit(1)
    }
    print("PASS Ed25519 signature: \(URL(fileURLWithPath: CommandLine.arguments[2]).lastPathComponent)")
} catch {
    fputs("FAIL update verification: \(error.localizedDescription)\n", stderr)
    exit(1)
}
