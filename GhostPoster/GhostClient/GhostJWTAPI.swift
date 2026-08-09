import CryptoKit
import Foundation

enum GhostJWT {
    static func makeToken(adminAPIKey: String, now: Date = Date()) throws -> String {
        let parts = adminAPIKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)

        guard parts.count == 2,
              parts[0].count == 24,
              parts[1].count == 64,
              parts.allSatisfy({ $0.allSatisfy(\.isHexDigit) }) else {
            throw GhostError.invalidAdminAPIKey
        }

        let keyID = String(parts[0])
        guard let secret = Data(hexString: String(parts[1])) else {
            throw GhostError.invalidAdminAPIKey
        }

        let issuedAt = Int(now.timeIntervalSince1970)
        let header = try encodeJSON([
            "alg": "HS256",
            "kid": keyID,
            "typ": "JWT"
        ])
        let payload = try encodeJSON([
            "iat": issuedAt,
            "exp": issuedAt + 300,
            "aud": "/admin/"
        ])

        let unsignedToken = "\(header.base64URLEncodedString()).\(payload.base64URLEncodedString())"
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(unsignedToken.utf8),
            using: SymmetricKey(data: secret)
        )

        return "\(unsignedToken).\(Data(signature).base64URLEncodedString())"
    }

    private static func encodeJSON(_ object: [String: Any]) throws -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        } catch {
            throw GhostError.jwtGenerationFailed
        }
    }
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex

        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
