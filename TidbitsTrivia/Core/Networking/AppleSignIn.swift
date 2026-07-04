import Foundation
import CryptoKit

/// Nonce helpers for Sign in with Apple + Firebase. The SwiftUI `SignInWithAppleButton`
/// drives the sheet; its `onRequest` sets `request.nonce = AppleNonce.sha256(raw)` and the
/// completion hands the identity token + the RAW nonce to `PlayerIdentityStore.linkApple`,
/// which Firebase verifies (it hashes the raw nonce and compares to the token's claim).
enum AppleNonce {
    static func random(_ length: Int = 32) -> String {
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var byte: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess else { continue }
            if Int(byte) < chars.count { result.append(chars[Int(byte)]); remaining -= 1 }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
