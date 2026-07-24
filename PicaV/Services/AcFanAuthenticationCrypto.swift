import CommonCrypto
import CryptoKit
import Foundation
import Security

enum AcFanAuthenticationCrypto {
    static func makeTravelerKey() throws -> String {
        try randomData(count: 12).map { String(format: "%02x", $0) }.joined()
    }

    static func encryptParameters(
        _ parameters: JSONObject,
        publicKeyPEM: String
    ) throws -> JSONObject {
        let symmetricKeyData = try randomData(count: 32)
        let nonceData = try randomData(count: 12)
        let plaintext = try JSONSerialization.data(withJSONObject: parameters)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealed = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: symmetricKeyData),
            nonce: nonce
        )
        var encryptedData = sealed.ciphertext
        encryptedData.append(sealed.tag)

        let publicKey = try rsaPublicKey(from: publicKeyPEM)
        var encryptionError: Unmanaged<CFError>?
        guard let encryptedKey = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionOAEPSHA256,
            symmetricKeyData as CFData,
            &encryptionError
        ) as Data? else {
            if let encryptionError {
                throw encryptionError.takeRetainedValue()
            }
            throw AnimeAPIError.authenticationFailed
        }

        return [
            "encryptedKey": encryptedKey.base64EncodedString(),
            "iv": nonceData.base64EncodedString(),
            "encryptedData": encryptedData.base64EncodedString()
        ]
    }

    static func sensitiveHeaders(
        method: PlatformHTTPMethod,
        path: String,
        body: JSONObject?
    ) throws -> [String: String] {
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1_000))
        let nonce = UUID().uuidString.lowercased()
        let bodyHash = SHA256.hash(data: try stableJSONData(body))
            .map { String(format: "%02x", $0) }
            .joined()
        let signatureSource = [
            method.rawValue,
            path,
            timestamp,
            nonce,
            bodyHash,
            "aB3!k9$zL2@mQ8#xV5^nY7*pW1(jH4&"
        ].joined(separator: "\n")
        let signature = SHA256.hash(data: Data(signatureSource.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        return [
            "X-Sensitive-Action": "1",
            "X-Request-Timestamp": timestamp,
            "X-Request-Nonce": nonce,
            "X-Request-Body-SHA256": bodyHash,
            "X-Request-Signature": signature
        ]
    }

    static func decryptTravelerResponse(
        _ encrypted: String,
        travelerKey: String,
        timestamp: String
    ) throws -> Any {
        guard let encryptedData = Data(base64Encoded: encrypted) else {
            throw AnimeAPIError.authenticationFailed
        }

        var starts: [Int] = []
        if let timestamp = Int64(timestamp) {
            starts.append(Int(timestamp % 8))
        }
        starts.append(contentsOf: 0...max(0, travelerKey.count - 16))

        var visited = Set<Int>()
        for start in starts where visited.insert(start).inserted {
            guard let key = travelerDecryptionKey(from: travelerKey, start: start),
                  let plaintext = decryptECB(encryptedData, key: Data(key.utf8)) else {
                continue
            }
            if let json = try? JSONSerialization.jsonObject(with: plaintext) {
                return json
            }
            if let text = String(data: plaintext, encoding: .utf8), !text.isEmpty {
                return text
            }
        }
        throw AnimeAPIError.authenticationFailed
    }

    private static func randomData(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }
        guard status == errSecSuccess else { throw AnimeAPIError.authenticationFailed }
        return data
    }

    private static func rsaPublicKey(from pem: String) throws -> SecKey {
        let base64 = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let data = Data(base64Encoded: base64) else {
            throw AnimeAPIError.authenticationFailed
        }

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic
        ]

        var lastError: CFError?
        for candidate in [data, extractPKCS1Key(fromSPKI: data)].compactMap({ $0 }) {
            var error: Unmanaged<CFError>?
            if let key = SecKeyCreateWithData(
                candidate as CFData,
                attributes as CFDictionary,
                &error
            ) {
                return key
            }
            lastError = error?.takeRetainedValue()
        }
        if let lastError { throw lastError }
        throw AnimeAPIError.authenticationFailed
    }

    private static func extractPKCS1Key(fromSPKI data: Data) -> Data? {
        let bytes = [UInt8](data)
        var index = 0

        guard consumeTag(0x30, bytes: bytes, index: &index) != nil,
              let algorithmLength = consumeTag(0x30, bytes: bytes, index: &index),
              index + algorithmLength <= bytes.count else {
            return nil
        }
        index += algorithmLength

        guard let bitStringLength = consumeTag(0x03, bytes: bytes, index: &index),
              bitStringLength > 1,
              index + bitStringLength <= bytes.count,
              bytes[index] == 0 else {
            return nil
        }
        index += 1
        return Data(bytes[index..<(index + bitStringLength - 1)])
    }

    private static func consumeTag(
        _ expected: UInt8,
        bytes: [UInt8],
        index: inout Int
    ) -> Int? {
        guard index < bytes.count, bytes[index] == expected else { return nil }
        index += 1
        guard index < bytes.count else { return nil }

        let first = Int(bytes[index])
        index += 1
        if first < 0x80 { return first }

        let lengthByteCount = first & 0x7F
        guard (1...4).contains(lengthByteCount), index + lengthByteCount <= bytes.count else {
            return nil
        }
        var length = 0
        for _ in 0..<lengthByteCount {
            length = (length << 8) | Int(bytes[index])
            index += 1
        }
        return length
    }

    private static func stableJSONData(_ body: JSONObject?) throws -> Data {
        if let body {
            return try JSONSerialization.data(
                withJSONObject: body,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
        }
        return Data("\"\"".utf8)
    }

    private static func travelerDecryptionKey(from key: String, start: Int) -> String? {
        let characters = Array(key)
        guard start >= 0, start + 16 <= characters.count else { return nil }
        return String(characters[start..<(start + 16)].reversed())
    }

    private static func decryptECB(_ encrypted: Data, key: Data) -> Data? {
        var output = Data(count: encrypted.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            encrypted.withUnsafeBytes { encryptedBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                        keyBytes.baseAddress,
                        key.count,
                        nil,
                        encryptedBytes.baseAddress,
                        encrypted.count,
                        outputBytes.baseAddress,
                        outputCapacity,
                        &outputLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        output.removeSubrange(outputLength..<output.count)
        return output
    }
}
