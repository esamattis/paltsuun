import CryptoKit
import Foundation

/// Helpers for OAuth 2.0 authorization code flows with PKCE (RFC 7636).
enum OAuth {
    /// A random string usable as a PKCE code verifier or `state`.
    static func randomToken() -> String {
        base64URL(Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }))
    }

    /// The S256 code challenge for `verifier`.
    static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Encodes parameters for a query string or an `application/x-www-form-urlencoded` body.
    static func formEncoded(_ parameters: [(String, String)]) -> String {
        parameters.map { "\(percentEncoded($0))=\(percentEncoded($1))" }.joined(separator: "&")
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func percentEncoded(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: unreserved) ?? string
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
