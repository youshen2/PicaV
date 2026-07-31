import Foundation

enum AppNetworkRoutingMode:
    String, Codable, CaseIterable, Identifiable, Sendable {
    case direct
    case proxyServer
    case builtInProxy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .direct:
            return "直连"
        case .proxyServer:
            return "代理服务器"
        case .builtInProxy:
            return "内置代理"
        }
    }

    var explanation: String {
        switch self {
        case .direct:
            return "应用直接连接目标服务器。"
        case .proxyServer:
            return "把请求交给已存在的 HTTP、HTTPS 或 SOCKS5 代理服务器。"
        case .builtInProxy:
            return "应用读取 Clash YAML 节点，并在进程内完成 SS、VMess、Trojan 等协议握手。"
        }
    }
}

enum AppBuiltInProxyKind:
    String, Codable, CaseIterable, Identifiable, Sendable {
    case http
    case socks5
    case shadowsocks
    case vmess
    case trojan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .http:
            return "HTTP"
        case .socks5:
            return "SOCKS5"
        case .shadowsocks:
            return "Shadowsocks"
        case .vmess:
            return "VMess"
        case .trojan:
            return "Trojan"
        }
    }

    var requiresSecret: Bool {
        switch self {
        case .http, .socks5:
            return false
        case .shadowsocks, .vmess, .trojan:
            return true
        }
    }
}

struct AppBuiltInProxyProfile:
    Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let kind: AppBuiltInProxyKind
    let server: String
    let port: UInt16
    let secretRef: String?
    let skipCertificateVerification: Bool

    var displayAddress: String {
        "\(server):\(port)"
    }
}

struct AppBuiltInProxySecret: Codable, Hashable, Sendable {
    let username: String?
    let password: String?
    let uuid: String?
    let alterID: Int?
    let cipher: String?
    let sni: String?

    static let empty = AppBuiltInProxySecret(
        username: nil,
        password: nil,
        uuid: nil,
        alterID: nil,
        cipher: nil,
        sni: nil
    )

    var isEmpty: Bool {
        [username, password, uuid, cipher, sni].allSatisfy {
            ($0 ?? "").isEmpty
        } && alterID == nil
    }

    var serverCredentials: AppProxyCredentials {
        AppProxyCredentials(
            username: username ?? "",
            password: password ?? ""
        )
    }
}

struct AppBuiltInProxyCandidate: Hashable, Sendable {
    let name: String
    let kind: AppBuiltInProxyKind
    let server: String
    let port: UInt16
    let secret: AppBuiltInProxySecret
    let skipCertificateVerification: Bool

    var identity: String {
        [
            name.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ),
            kind.rawValue,
            server.lowercased(),
            String(port)
        ].joined(separator: "|")
    }
}

struct AppBuiltInProxyImportSummary: Sendable {
    let importedCount: Int
    let replacedCount: Int
    let skippedMessages: [String]

    var message: String {
        var parts = ["已导入 \(importedCount) 个节点"]
        if replacedCount > 0 {
            parts.append("其中更新 \(replacedCount) 个")
        }
        if !skippedMessages.isEmpty {
            parts.append("跳过 \(skippedMessages.count) 个")
        }
        return parts.joined(separator: "，") + "。"
    }
}
