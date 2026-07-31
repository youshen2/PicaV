import CommonCrypto
import Foundation

struct ServerPayload {
    let value: Any
    let domain: String?
}

enum AnimeResponseParser {
    static func parse(
        data: Data,
        statusCode: Int,
        travelerKey: String?,
        timestamp: String,
        accessToken: String
    ) async throws -> ServerPayload {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try parseSynchronously(
                data: data,
                statusCode: statusCode,
                travelerKey: travelerKey,
                timestamp: timestamp,
                accessToken: accessToken
            )
        }
        return try await withTaskCancellationHandler {
            do {
                let payload = try await task.value
                try Task.checkCancellation()
                return payload
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            task.cancel()
        }
    }

    private static func parseSynchronously(
        data: Data,
        statusCode: Int,
        travelerKey: String?,
        timestamp: String,
        accessToken: String
    ) throws -> ServerPayload {
        let parsedObject = try? JSONSerialization.jsonObject(with: data)
        try Task.checkCancellation()
        let parsedRoot = parsedObject as? JSONObject
        guard (200...299).contains(statusCode) else {
            throw AnimeAPIError.httpStatus(
                statusCode,
                message: parsedRoot?.string(for: ["msg", "message", "error"])
            )
        }
        guard let root = parsedRoot else {
            throw AnimeAPIError.invalidResponse
        }
        return try parsePayload(
            root,
            travelerKey: travelerKey,
            timestamp: timestamp,
            accessToken: accessToken
        )
    }

    private static func parsePayload(
        _ root: JSONObject,
        travelerKey: String?,
        timestamp: String,
        accessToken: String
    ) throws -> ServerPayload {
        try Task.checkCancellation()
        if let code = root.integer(for: ["code", "status"]),
           code != 0,
           code != 200 {
            throw AnimeAPIError.server(
                code: code,
                message: root.string(
                    for: ["msg", "message", "error"]
                ) ?? "请求失败（\(code)）"
            )
        }

        let dataObject = root.object(for: ["data", "result"])
        let rootDomain = root.string(
            for: ["domain", "imgDomain", "imageDomain"]
        ) ?? dataObject?.string(
            for: ["domain", "imgDomain", "imageDomain"]
        )

        if let travelerKey,
           let encrypted = root.string(for: ["data"]) {
            try Task.checkCancellation()
            let value = try AcFanAuthenticationCrypto.decryptTravelerResponse(
                encrypted,
                travelerKey: travelerKey,
                timestamp: timestamp
            )
            return normalizedPayload(value, fallbackDomain: rootDomain)
        }

        let encrypted = root.string(for: ["encData"])
            ?? dataObject?.string(for: ["encData"])
        if let encrypted {
            try Task.checkCancellation()
            return normalizedPayload(
                try decryptJSON(encrypted, accessToken: accessToken),
                fallbackDomain: rootDomain
            )
        }
        return ServerPayload(
            value: root.value(for: ["data", "result"]) ?? root,
            domain: rootDomain
        )
    }

    private static func normalizedPayload(
        _ value: Any,
        fallbackDomain: String?
    ) -> ServerPayload {
        guard let object = value as? JSONObject else {
            return ServerPayload(value: value, domain: fallbackDomain)
        }
        let domain = object.string(
            for: ["domain", "imgDomain", "imageDomain"]
        ) ?? object.object(for: ["data", "result"])?.string(
            for: ["domain", "imgDomain", "imageDomain"]
        ) ?? fallbackDomain
        let isEnvelope = object.value(for: ["code", "status"]) != nil
            || (
                object.value(
                    for: ["domain", "imgDomain", "imageDomain"]
                ) != nil
                    && object.value(for: ["data", "result"]) != nil
            )
        if isEnvelope, let nested = object.value(for: ["data", "result"]) {
            return ServerPayload(value: nested, domain: domain)
        }
        return ServerPayload(value: object, domain: domain)
    }

    private static func decryptJSON(
        _ encrypted: String,
        accessToken: String
    ) throws -> Any {
        try Task.checkCancellation()
        let keyString = String(accessToken.dropFirst(2).prefix(16))
        guard keyString.utf8.count == kCCKeySizeAES128 else {
            throw AnimeAPIError.missingDecryptionKey
        }
        guard let encryptedData = Data(base64Encoded: encrypted) else {
            throw AnimeAPIError.decryptionFailed
        }

        let key = Data(keyString.utf8)
        var output = Data(count: encryptedData.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            encryptedData.withUnsafeBytes { encryptedBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        key.count,
                        keyBytes.baseAddress,
                        encryptedBytes.baseAddress,
                        encryptedData.count,
                        outputBytes.baseAddress,
                        outputCapacity,
                        &outputLength
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw AnimeAPIError.decryptionFailed
        }
        try Task.checkCancellation()
        output.removeSubrange(outputLength..<output.count)
        return try JSONSerialization.jsonObject(with: output)
    }
}
