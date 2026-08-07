import Foundation

struct AcFanDiscoveredAPIAddress: Equatable {
    let baseURLText: String
    let discoveredURL: URL
}

enum AcFanAPIAddressDiscovery {
    static func discover(
        route: AppNetworkRoute,
        session injectedSession: URLSession? = nil
    ) async throws -> AcFanDiscoveredAPIAddress {
        let session = injectedSession
            ?? AppNetworkSessionFactory.shared.session(
                for: route,
                purpose: .addressDiscovery
            )
        let landingURL = try await resolveLandingURL(using: session)
        let listURL = try addressListURL(for: landingURL)
        let data = try await fetchAddressList(from: listURL, using: session)
        return try parseAddressList(data)
    }

    static func parseAddressList(
        _ data: Data
    ) throws -> AcFanDiscoveredAPIAddress {
        let payload: Any
        do {
            payload = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw DiscoveryError.invalidPayload
        }
        guard let domain = onlineH5Domain(in: payload) else {
            throw DiscoveryError.onlineH5AddressMissing
        }
        return try normalizedAddress(from: domain)
    }

    private static func resolveLandingURL(
        using session: URLSession
    ) async throws -> URL {
        var request = URLRequest(
            url: entryURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        )
        request.httpMethod = "GET"
        request.setValue(
            "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )

        let delegate = HTTPSRedirectDelegate()
        let (bytes, response) = try await session.bytes(
            for: request,
            delegate: delegate
        )
        try validate(response: response, redirectDelegate: delegate)
        if response.expectedContentLength > Int64(maximumLandingPageSize) {
            throw DiscoveryError.responseTooLarge
        }
        let data = try await collect(
            bytes,
            maximumSize: maximumLandingPageSize
        )
        if let finalURL = response.url, isWorkURL(finalURL) {
            return finalURL
        }
        guard let scriptURL = scriptRedirectURL(from: data) else {
            throw DiscoveryError.workRedirectMissing
        }
        return scriptURL
    }

    private static func fetchAddressList(
        from url: URL,
        using session: URLSession
    ) async throws -> Data {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        )
        request.httpMethod = "GET"
        request.setValue(
            "application/json, text/plain;q=0.9, */*;q=0.8",
            forHTTPHeaderField: "Accept"
        )

        let delegate = HTTPSRedirectDelegate()
        let (bytes, response) = try await session.bytes(
            for: request,
            delegate: delegate
        )
        try validate(response: response, redirectDelegate: delegate)
        if response.expectedContentLength > Int64(maximumResponseSize) {
            throw DiscoveryError.responseTooLarge
        }
        return try await collect(
            bytes,
            maximumSize: maximumResponseSize
        )
    }

    private static func validate(
        response: URLResponse,
        redirectDelegate: HTTPSRedirectDelegate
    ) throws {
        if redirectDelegate.rejectedInsecureRedirect {
            throw DiscoveryError.insecureRedirect
        }
        guard let response = response as? HTTPURLResponse else {
            throw DiscoveryError.invalidResponse
        }
        guard response.url?.scheme?.lowercased() == "https" else {
            throw DiscoveryError.insecureRedirect
        }
        guard (200..<300).contains(response.statusCode) else {
            throw DiscoveryError.httpStatus(response.statusCode)
        }
    }

    private static func addressListURL(for landingURL: URL) throws -> URL {
        guard var components = URLComponents(
            url: landingURL,
            resolvingAgainstBaseURL: false
        ), components.scheme?.lowercased() == "https",
        let host = components.host,
        isWorkHost(host) else {
            throw DiscoveryError.workRedirectMissing
        }
        components.user = nil
        components.password = nil
        components.path = addressListPath
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw DiscoveryError.invalidResponse
        }
        return url
    }

    private static func collect(
        _ bytes: URLSession.AsyncBytes,
        maximumSize: Int
    ) async throws -> Data {
        var data = Data()
        data.reserveCapacity(8 * 1_024)
        for try await byte in bytes {
            guard data.count < maximumSize else {
                throw DiscoveryError.responseTooLarge
            }
            data.append(byte)
        }
        return data
    }

    private static func scriptRedirectURL(from data: Data) -> URL? {
        guard let html = String(data: data, encoding: .utf8),
              let expression = scriptRedirectExpression else {
            return nil
        }
        let searchRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = expression.firstMatch(
            in: html,
            options: [],
            range: searchRange
        ), let valueRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let value = String(html[valueRange]).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let url = URL(string: value), isWorkURL(url) else {
            return nil
        }
        return url
    }

    private static func onlineH5Domain(in value: Any) -> String? {
        if let object = value as? [String: Any] {
            let remark = stringValue(for: "remark", in: object)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if remark == targetRemark,
               let domain = stringValue(for: "domain", in: object)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !domain.isEmpty {
                return domain
            }

            for key in preferredContainerKeys {
                if let nestedValue = caseInsensitiveValue(
                    for: key,
                    in: object
                ),
                   let domain = onlineH5Domain(in: nestedValue) {
                    return domain
                }
            }
            for key in object.keys.sorted()
            where !preferredContainerKeys.contains(key.lowercased()) {
                if let nestedValue = object[key],
                   let domain = onlineH5Domain(in: nestedValue) {
                    return domain
                }
            }
        } else if let array = value as? [Any] {
            for item in array {
                if let domain = onlineH5Domain(in: item) {
                    return domain
                }
            }
        }
        return nil
    }

    private static func stringValue(
        for key: String,
        in object: [String: Any]
    ) -> String? {
        caseInsensitiveValue(for: key, in: object) as? String
    }

    private static func caseInsensitiveValue(
        for key: String,
        in object: [String: Any]
    ) -> Any? {
        if let value = object[key] {
            return value
        }
        return object.first {
            $0.key.caseInsensitiveCompare(key) == .orderedSame
        }?.value
    }

    private static func normalizedAddress(
        from rawDomain: String
    ) throws -> AcFanDiscoveredAPIAddress {
        let trimmed = rawDomain.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty, trimmed.utf8.count <= maximumURLSize else {
            throw DiscoveryError.invalidAPIAddress
        }

        let candidate: String
        if trimmed.hasPrefix("//") {
            candidate = "https:" + trimmed
        } else if trimmed.contains("://") {
            candidate = trimmed
        } else {
            candidate = "https://" + trimmed
        }
        guard var components = URLComponents(string: candidate),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil else {
            throw DiscoveryError.invalidAPIAddress
        }

        let path = components.percentEncodedPath.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        components.percentEncodedPath = ""
        components.query = nil
        components.fragment = nil
        guard let baseURL = components.url else {
            throw DiscoveryError.invalidAPIAddress
        }

        let baseURLText = baseURL.absoluteString.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        let discoveredPath = path.isEmpty ? "" : "/" + path
        guard let discoveredURL = URL(
            string: baseURLText + discoveredPath
        ) else {
            throw DiscoveryError.invalidAPIAddress
        }
        return AcFanDiscoveredAPIAddress(
            baseURLText: baseURLText,
            discoveredURL: discoveredURL
        )
    }

    private static func isWorkHost(_ host: String) -> Bool {
        host.lowercased().hasSuffix(".work")
    }

    private static func isWorkURL(_ url: URL) -> Bool {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ), components.scheme?.lowercased() == "https",
        let host = components.host,
        isWorkHost(host),
        components.user == nil,
        components.password == nil else {
            return false
        }
        return true
    }

    enum DiscoveryError: LocalizedError {
        case insecureRedirect
        case workRedirectMissing
        case invalidResponse
        case httpStatus(Int)
        case responseTooLarge
        case invalidPayload
        case onlineH5AddressMissing
        case invalidAPIAddress

        var errorDescription: String? {
            switch self {
            case .insecureRedirect:
                return "地址服务尝试跳转到非 HTTPS 页面，已停止更新。"
            case .workRedirectMissing:
                return "acfan.com 未提供有效的 HTTPS .work 跳转地址。"
            case .invalidResponse:
                return "地址服务没有返回有效的 HTTP 响应。"
            case .httpStatus(let statusCode):
                return "地址服务返回 HTTP \(statusCode)。"
            case .responseTooLarge:
                return "地址服务响应过大，已停止读取。"
            case .invalidPayload:
                return "地址列表不是有效的 JSON 数据。"
            case .onlineH5AddressMissing:
                return "地址列表中没有找到“在线H5观看”。"
            case .invalidAPIAddress:
                return "“在线H5观看”对应的 API 地址无效。"
            }
        }
    }

    private static let entryURL = URL(string: "https://acfan.com")!
    private static let addressListPath = "/web/new/address/api/list"
    private static let targetRemark = "在线H5观看"
    private static let scriptRedirectExpression = try? NSRegularExpression(
        pattern: #"(?:document|window)\s*\.\s*location(?:\s*\.\s*href)?\s*=\s*['\"]([^'\"]+)['\"]"#,
        options: [.caseInsensitive]
    )
    private static let preferredContainerKeys = [
        "data",
        "list",
        "rows",
        "result"
    ]
    private static let maximumLandingPageSize = 64 * 1_024
    private static let maximumResponseSize = 1 * 1_024 * 1_024
    private static let maximumURLSize = 16 * 1_024
}

private final class HTTPSRedirectDelegate:
    NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    var rejectedInsecureRedirect: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _rejectedInsecureRedirect
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard request.url?.scheme?.lowercased() == "https" else {
            lock.lock()
            _rejectedInsecureRedirect = true
            lock.unlock()
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    private let lock = NSLock()
    private var _rejectedInsecureRedirect = false
}
