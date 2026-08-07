import Combine
import Foundation

enum AppSettingsValidationError: LocalizedError {
    case invalidServerURL
    case invalidAPIPrefix

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "请输入有效的 HTTPS 服务器地址。"
        case .invalidAPIPrefix:
            return "API 前缀不能包含查询参数或片段。"
        }
    }
}

final class AppSettings: ObservableObject {
    static let defaultBaseURL = AnimePlatformRegistry.defaultAdapter.defaultBaseURL
    static let defaultAPIPrefix = AnimePlatformRegistry.defaultAdapter.defaultAPIPrefix

    @Published private(set) var platformID: AnimePlatformID
    @Published private(set) var contentContextRevision = 0

    @Published private(set) var baseURLText: String {
        didSet {
            guard !isApplyingServerConfiguration else { return }
            defaults.set(baseURLText, forKey: scopedKey(Keys.baseURL))
            invalidateGuestSession()
        }
    }

    @Published private(set) var apiPrefix: String {
        didSet {
            guard !isApplyingServerConfiguration else { return }
            defaults.set(apiPrefix, forKey: scopedKey(Keys.apiPrefix))
            invalidateGuestSession()
        }
    }

    @Published private(set) var accessToken: String {
        didSet {
            let key = scopedKey(Keys.accessToken)
            if accessToken.isEmpty {
                KeychainStore.remove(key)
            } else {
                KeychainStore.set(accessToken, for: key)
            }
        }
    }

    @Published private(set) var accountSession: PlatformAccountSession?

    @Published private(set) var imageDomain: String

    @Published var preferredCDNID: String {
        didSet { defaults.set(preferredCDNID, forKey: scopedKey(Keys.preferredCDNID)) }
    }

    @Published var autoplayNextEpisode: Bool {
        didSet { defaults.set(autoplayNextEpisode, forKey: Keys.autoplayNextEpisode) }
    }

    @Published var downloadOverCellular: Bool {
        didSet {
            defaults.set(
                downloadOverCellular,
                forKey: Keys.downloadOverCellular
            )
        }
    }

    @Published var useImageProxy: Bool {
        didSet { defaults.set(useImageProxy, forKey: Keys.useImageProxy) }
    }

    @Published private(set) var appProxyEnabled: Bool
    @Published private(set) var appProxyConfiguration: AppProxyConfiguration?
    @Published private(set) var appNetworkRoutingMode:
        AppNetworkRoutingMode
    @Published private(set) var appBuiltInProxyProfiles:
        [AppBuiltInProxyProfile]
    @Published private(set) var selectedBuiltInProxyID: UUID?
    @Published private(set) var appProxyRevision = 0

    @Published private(set) var guestSessionActive: Bool

    let deviceID: String
    let requestSID: String

    var activePlatform: AnimePlatformAdapter {
        AnimePlatformRegistry.adapter(for: platformID)
    }

    var contentContextIdentity: String {
        "\(platformID.rawValue)|\(contentContextRevision)|\(appProxyRevision)"
    }

    var effectiveAccessToken: String {
        accessToken.isEmpty ? guestToken : accessToken
    }

    var isAccountLoggedIn: Bool {
        !accessToken.isEmpty
    }

    var rootURL: URL {
        let entered = baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = entered.contains("://") ? entered : "https://\(entered)"
        return URL(string: withScheme) ?? URL(string: activePlatform.defaultBaseURL)!
    }

    var apiBaseURL: URL {
        let root = rootURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: root + normalizedAPIPrefix)
            ?? URL(string: activePlatform.defaultBaseURL + activePlatform.defaultAPIPrefix)!
    }

    var effectiveImageDomain: String? {
        if !imageDomain.isEmpty {
            return imageDomain
        }
        guard let fallbackHost = activePlatform.imageConfiguration.fallbackHost else {
            return nil
        }
        return fallbackHost.contains("://") ? fallbackHost : "https://\(fallbackHost)"
    }

    var normalizedAPIPrefix: String {
        let trimmed = apiPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "/" else { return "" }
        return "/" + trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let selectedPlatform = AnimePlatformID(
            rawValue: defaults.string(forKey: Keys.platformID) ?? ""
        ) ?? AnimePlatformRegistry.defaultID
        let platformKey: (String) -> String = {
            Self.scopedKey($0, platformID: selectedPlatform)
        }
        let snapshot = Self.platformSettings(
            for: selectedPlatform,
            defaults: defaults,
            includesLegacyValues: true
        )

        platformID = selectedPlatform
        baseURLText = snapshot.baseURLText
        apiPrefix = snapshot.apiPrefix
        accessToken = snapshot.accessToken
        accountSession = snapshot.accountSession
        imageDomain = snapshot.imageDomain
        preferredCDNID = snapshot.preferredCDNID
        guestToken = ""
        guestSessionActive = false
        requestSID = Self.randomHex(length: 32)

        if defaults.object(forKey: Keys.autoplayNextEpisode) == nil {
            autoplayNextEpisode = true
        } else {
            autoplayNextEpisode = defaults.bool(forKey: Keys.autoplayNextEpisode)
        }

        if defaults.object(forKey: Keys.downloadOverCellular) == nil {
            downloadOverCellular = false
        } else {
            downloadOverCellular = defaults.bool(
                forKey: Keys.downloadOverCellular
            )
        }

        if defaults.object(forKey: Keys.useImageProxy) == nil {
            useImageProxy = true
        } else {
            useImageProxy = defaults.bool(forKey: Keys.useImageProxy)
        }

        appProxyConfiguration = Self.decodeProxyConfiguration(
            defaults.data(forKey: Keys.appProxyConfiguration)
        )
        appBuiltInProxyProfiles =
            AppBuiltInProxyProfileStore.decodeProfiles(
                defaults.data(forKey: Keys.appBuiltInProxyProfiles)
            )
        selectedBuiltInProxyID = defaults.string(
            forKey: Keys.selectedBuiltInProxyID
        ).flatMap(UUID.init(uuidString:))
        let resolvedRoutingMode: AppNetworkRoutingMode
        if let storedMode = defaults.string(
            forKey: Keys.appNetworkRoutingMode
        ).flatMap(AppNetworkRoutingMode.init(rawValue:)) {
            resolvedRoutingMode = storedMode
        } else if defaults.bool(forKey: Keys.appProxyEnabled) {
            resolvedRoutingMode = .proxyServer
        } else {
            resolvedRoutingMode = .direct
        }
        appNetworkRoutingMode = resolvedRoutingMode
        appProxyEnabled = resolvedRoutingMode != .direct

        if let existing = defaults.string(forKey: Keys.deviceID),
           Self.isValidAcFanDeviceID(existing) {
            deviceID = existing
        } else {
            let generated = String(("h5_" + Self.randomHex(length: 32)).prefix(32))
            defaults.set(generated, forKey: Keys.deviceID)
            deviceID = generated
        }

        if defaults.string(forKey: Keys.guestTokenScope) == sessionScope,
           let storedGuestToken = KeychainStore.string(for: Keys.guestToken),
           !storedGuestToken.isEmpty {
            guestToken = storedGuestToken
            guestSessionActive = true
        }

        if !snapshot.hadScopedAccessToken, !accessToken.isEmpty {
            KeychainStore.set(accessToken, for: platformKey(Keys.accessToken))
            KeychainStore.remove(Keys.legacyAccessToken)
        }
    }

    func selectPlatform(_ id: AnimePlatformID) {
        guard id != platformID else { return }
        invalidateGuestSession()

        platformID = id
        defaults.set(id.rawValue, forKey: Keys.platformID)
        let snapshot = Self.platformSettings(
            for: id,
            defaults: defaults,
            includesLegacyValues: false
        )
        isApplyingServerConfiguration = true
        baseURLText = snapshot.baseURLText
        apiPrefix = snapshot.apiPrefix
        isApplyingServerConfiguration = false
        accessToken = snapshot.accessToken
        accountSession = snapshot.accountSession
        imageDomain = snapshot.imageDomain
        preferredCDNID = snapshot.preferredCDNID
    }

    func restoreServerDefaults() {
        try? applyServerConfiguration(
            baseURLText: activePlatform.defaultBaseURL,
            apiPrefix: activePlatform.defaultAPIPrefix
        )
    }

    func applyServerConfiguration(
        baseURLText rawBaseURL: String,
        apiPrefix rawAPIPrefix: String
    ) throws {
        let entered = rawBaseURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let withScheme = entered.contains("://")
            ? entered
            : "https://\(entered)"
        guard var components = URLComponents(string: withScheme),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false else {
            throw AppSettingsValidationError.invalidServerURL
        }
        components.query = nil
        components.fragment = nil
        guard let normalizedURL = components.url else {
            throw AppSettingsValidationError.invalidServerURL
        }

        let trimmedPrefix = rawAPIPrefix.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedPrefix.contains("?"),
              !trimmedPrefix.contains("#") else {
            throw AppSettingsValidationError.invalidAPIPrefix
        }
        let normalizedBaseURL = normalizedURL.absoluteString
            .trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
        let normalizedPrefix: String
        if trimmedPrefix.isEmpty || trimmedPrefix == "/" {
            normalizedPrefix = ""
        } else {
            normalizedPrefix = "/"
                + trimmedPrefix.trimmingCharacters(
                    in: CharacterSet(charactersIn: "/")
                )
        }
        guard normalizedBaseURL != baseURLText
            || normalizedPrefix != apiPrefix else {
            return
        }

        isApplyingServerConfiguration = true
        baseURLText = normalizedBaseURL
        apiPrefix = normalizedPrefix
        isApplyingServerConfiguration = false
        defaults.set(baseURLText, forKey: scopedKey(Keys.baseURL))
        defaults.set(apiPrefix, forKey: scopedKey(Keys.apiPrefix))
        clearServerScopedSession()
        invalidateGuestSession()
        contentContextRevision += 1
    }

    func setAccountSession(_ session: PlatformAccountSession, accessToken token: String) {
        guard session.platformID == platformID, !token.isEmpty else { return }
        accessToken = token
        accountSession = session
        defaults.set(
            try? JSONEncoder().encode(session),
            forKey: scopedKey(Keys.accountSession)
        )
        invalidateGuestSession()
        contentContextRevision += 1
    }

    func setImageDomain(_ rawValue: String?) {
        guard let rawValue else { return }
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if value.hasPrefix("//") {
            value = "https:" + value
        } else if !value.contains("://") {
            value = "https://" + value
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard URL(string: value)?.host != nil, value != imageDomain else { return }
        imageDomain = value
        defaults.set(value, forKey: scopedKey(Keys.imageDomain))
    }

    func logoutCurrentAccount() {
        let hadAccount = isAccountLoggedIn || accountSession != nil
        accessToken = ""
        accountSession = nil
        defaults.removeObject(forKey: scopedKey(Keys.accountSession))
        invalidateGuestSession()
        if hadAccount {
            contentContextRevision += 1
        }
    }

    func setGuestToken(_ token: String) {
        guard !token.isEmpty else { return }
        guestToken = token
        KeychainStore.set(token, for: Keys.guestToken)
        defaults.set(sessionScope, forKey: Keys.guestTokenScope)
        guestSessionActive = true
    }

    func setRefreshedSessionToken(_ token: String) {
        guard !token.isEmpty else { return }
        if accessToken.isEmpty {
            setGuestToken(token)
        } else {
            accessToken = token
        }
    }

    func invalidateExpiredSession() {
        if accessToken.isEmpty {
            invalidateGuestSession()
        } else {
            logoutCurrentAccount()
        }
    }

    func invalidateGuestSession() {
        guestToken = ""
        KeychainStore.remove(Keys.guestToken)
        defaults.removeObject(forKey: Keys.guestTokenScope)
        guestSessionActive = false
    }

    func applyAppProxyConfiguration(
        type: AppProxyProtocol,
        host: String,
        port: String,
        username: String,
        password: String
    ) throws {
        let (configuration, credentials) =
            try AppProxyConfigurationParser.validated(
                type: type,
                host: host,
                port: port,
                username: username,
                password: password
            )
        let credentialData = try JSONEncoder().encode(credentials)
        guard let credentialValue = String(
            data: credentialData,
            encoding: .utf8
        ) else {
            throw KeychainStoreError.operationFailed(errSecDecode)
        }
        try KeychainStore.setSecure(
            credentialValue,
            for: Keys.appProxyCredentials
        )

        let wasUsingProxyServer =
            appNetworkRoutingMode == .proxyServer
        appProxyConfiguration = configuration
        defaults.set(
            try JSONEncoder().encode(configuration),
            forKey: Keys.appProxyConfiguration
        )
        if wasUsingProxyServer {
            appProxyDidChange()
        } else {
            activateRoutingMode(.proxyServer)
        }
    }

    func disableAppProxy() {
        activateRoutingMode(.direct)
    }

    func setNetworkRoutingMode(
        _ mode: AppNetworkRoutingMode
    ) throws {
        switch mode {
        case .direct:
            break
        case .proxyServer:
            guard appProxyConfiguration != nil else {
                throw AppProxyError.configurationMissing
            }
        case .builtInProxy:
            guard let profile = selectedBuiltInProxyProfile else {
                throw AppProxyError.builtInProfileMissing
            }
            _ = try AppBuiltInProxyProfileStore.secret(for: profile)
        }
        activateRoutingMode(mode)
    }

    @discardableResult
    func importBuiltInProxyYAML(
        _ yaml: String
    ) throws -> AppBuiltInProxyImportSummary {
        try importBuiltInProxyParseResult(
            ClashYAMLProxyParser.parse(yaml)
        )
    }

    @discardableResult
    func importBuiltInProxyParseResult(
        _ parsed: ClashYAMLProxyParser.ParseResult
    ) throws -> AppBuiltInProxyImportSummary {
        guard !parsed.candidates.isEmpty else {
            throw ClashYAMLProxyParser.ParseError.noSupportedNodes(
                parsed.skippedMessages
            )
        }
        let result = try AppBuiltInProxyProfileStore.importCandidates(
            parsed.candidates,
            into: appBuiltInProxyProfiles,
            defaults: defaults,
            storageKey: Keys.appBuiltInProxyProfiles
        )
        appBuiltInProxyProfiles = result.profiles
        if selectedBuiltInProxyProfile == nil {
            selectedBuiltInProxyID = result.profiles.first?.id
            persistSelectedBuiltInProxyID()
        }
        appProxyDidChange()
        return AppBuiltInProxyImportSummary(
            importedCount: result.importedCount,
            replacedCount: result.replacedCount,
            skippedMessages: parsed.skippedMessages
        )
    }

    func selectBuiltInProxyProfile(_ id: UUID) throws {
        guard let profile = appBuiltInProxyProfiles.first(where: {
            $0.id == id
        }) else {
            throw AppProxyError.builtInProfileMissing
        }
        _ = try AppBuiltInProxyProfileStore.secret(for: profile)
        let selectionChanged = selectedBuiltInProxyID != id
        selectedBuiltInProxyID = id
        persistSelectedBuiltInProxyID()
        if appNetworkRoutingMode == .builtInProxy {
            if selectionChanged {
                appProxyDidChange()
            }
        } else {
            activateRoutingMode(.builtInProxy)
        }
    }

    func removeBuiltInProxyProfile(_ id: UUID) throws {
        appBuiltInProxyProfiles =
            try AppBuiltInProxyProfileStore.remove(
                profileID: id,
                from: appBuiltInProxyProfiles,
                defaults: defaults,
                storageKey: Keys.appBuiltInProxyProfiles
            )
        if selectedBuiltInProxyID == id {
            selectedBuiltInProxyID = appBuiltInProxyProfiles.first?.id
            persistSelectedBuiltInProxyID()
        }
        appProxyDidChange()
    }

    var selectedBuiltInProxyProfile: AppBuiltInProxyProfile? {
        guard let selectedBuiltInProxyID else { return nil }
        return appBuiltInProxyProfiles.first {
            $0.id == selectedBuiltInProxyID
        }
    }

    func appProxyCredentials() -> AppProxyCredentials {
        guard let value = KeychainStore.string(
            for: Keys.appProxyCredentials
        ), let data = value.data(using: .utf8),
        let credentials = try? JSONDecoder().decode(
            AppProxyCredentials.self,
            from: data
        ) else {
            return .empty
        }
        return credentials
    }

    func appNetworkRoute() throws -> AppNetworkRoute {
        switch appNetworkRoutingMode {
        case .direct:
            return .direct
        case .proxyServer:
            return try networkRouteForProxyServer()
        case .builtInProxy:
            guard let profile = selectedBuiltInProxyProfile else {
                throw AppProxyError.builtInProfileMissing
            }
            return .proxy(
                .builtIn(
                    profile: profile,
                    secret: try AppBuiltInProxyProfileStore.secret(
                        for: profile
                    ),
                    revision: appProxyRevision
                )
            )
        }
    }

    func networkRouteForProxyServer() throws -> AppNetworkRoute {
        guard let configuration = appProxyConfiguration else {
            throw AppProxyError.configurationMissing
        }
        let credentials = appProxyCredentials()
        if configuration.requiresAuthentication,
           !credentials.isComplete {
            throw AppProxyError.credentialsUnavailable
        }
        return .proxy(
            .proxyServer(
                configuration: configuration,
                credentials: credentials,
                revision: appProxyRevision
            )
        )
    }

    func networkRoute(
        forBuiltInProxyProfileID id: UUID
    ) throws -> AppNetworkRoute {
        guard let profile = appBuiltInProxyProfiles.first(where: {
            $0.id == id
        }) else {
            throw AppProxyError.builtInProfileMissing
        }
        return .proxy(
            .builtIn(
                profile: profile,
                secret: try AppBuiltInProxyProfileStore.secret(
                    for: profile
                ),
                revision: appProxyRevision
            )
        )
    }

    private func clearServerScopedSession() {
        accessToken = ""
        accountSession = nil
        imageDomain = ""
        preferredCDNID = ""
        defaults.removeObject(forKey: scopedKey(Keys.accountSession))
        defaults.removeObject(forKey: scopedKey(Keys.imageDomain))
    }

    private var sessionScope: String {
        "\(platformID.rawValue)|\(baseURLText)|\(normalizedAPIPrefix)"
    }

    private func scopedKey(_ base: String) -> String {
        Self.scopedKey(base, platformID: platformID)
    }

    private static func scopedKey(_ base: String, platformID: AnimePlatformID) -> String {
        "\(base).\(platformID.rawValue)"
    }

    private static func decodeSession(_ data: Data?) -> PlatformAccountSession? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(PlatformAccountSession.self, from: data)
    }

    private static func decodeProxyConfiguration(
        _ data: Data?
    ) -> AppProxyConfiguration? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(
            AppProxyConfiguration.self,
            from: data
        )
    }

    private func appProxyDidChange() {
        appProxyRevision &+= 1
        AppNetworkSessionFactory.shared.reset()
    }

    private func activateRoutingMode(
        _ mode: AppNetworkRoutingMode
    ) {
        guard mode != appNetworkRoutingMode
                || appProxyEnabled != (mode != .direct) else {
            return
        }
        appNetworkRoutingMode = mode
        appProxyEnabled = mode != .direct
        defaults.set(
            mode.rawValue,
            forKey: Keys.appNetworkRoutingMode
        )
        defaults.set(
            appProxyEnabled,
            forKey: Keys.appProxyEnabled
        )
        appProxyDidChange()
    }

    private func persistSelectedBuiltInProxyID() {
        if let selectedBuiltInProxyID {
            defaults.set(
                selectedBuiltInProxyID.uuidString,
                forKey: Keys.selectedBuiltInProxyID
            )
        } else {
            defaults.removeObject(
                forKey: Keys.selectedBuiltInProxyID
            )
        }
    }

    private static func platformSettings(
        for platformID: AnimePlatformID,
        defaults: UserDefaults,
        includesLegacyValues: Bool
    ) -> PlatformSettingsSnapshot {
        let platform = AnimePlatformRegistry.adapter(for: platformID)
        let key: (String) -> String = {
            scopedKey($0, platformID: platformID)
        }
        let scopedAccessToken = KeychainStore.string(
            for: key(Keys.accessToken)
        )
        return PlatformSettingsSnapshot(
            baseURLText: defaults.string(forKey: key(Keys.baseURL))
                ?? (
                    includesLegacyValues
                        ? defaults.string(forKey: Keys.legacyBaseURL)
                        : nil
                )
                ?? platform.defaultBaseURL,
            apiPrefix: defaults.string(forKey: key(Keys.apiPrefix))
                ?? (
                    includesLegacyValues
                        ? defaults.string(forKey: Keys.legacyAPIPrefix)
                        : nil
                )
                ?? platform.defaultAPIPrefix,
            accessToken: scopedAccessToken
                ?? (
                    includesLegacyValues
                        ? KeychainStore.string(for: Keys.legacyAccessToken)
                        : nil
                )
                ?? "",
            accountSession: decodeSession(
                defaults.data(forKey: key(Keys.accountSession))
            ),
            imageDomain: defaults.string(
                forKey: key(Keys.imageDomain)
            ) ?? "",
            preferredCDNID: defaults.string(
                forKey: key(Keys.preferredCDNID)
            )
                ?? (
                    includesLegacyValues
                        ? defaults.string(
                            forKey: Keys.legacyPreferredCDNID
                        )
                        : nil
                )
                ?? "",
            hadScopedAccessToken: scopedAccessToken != nil
        )
    }

    private static func randomHex(length: Int) -> String {
        let value = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        if length <= value.count { return String(value.prefix(length)) }
        return String(repeating: value, count: (length / value.count) + 1).prefix(length).description
    }

    private static func isValidAcFanDeviceID(_ value: String) -> Bool {
        value.count == 32
            && value.hasPrefix("h5_")
            && value.dropFirst(3).allSatisfy { $0.isHexDigit }
    }

    private let defaults: UserDefaults
    private var guestToken: String
    private var isApplyingServerConfiguration = false

    private struct PlatformSettingsSnapshot {
        let baseURLText: String
        let apiPrefix: String
        let accessToken: String
        let accountSession: PlatformAccountSession?
        let imageDomain: String
        let preferredCDNID: String
        let hadScopedAccessToken: Bool
    }

    private enum Keys {
        static let platformID = "platform.id"
        static let baseURL = "server.baseURL"
        static let apiPrefix = "server.apiPrefix"
        static let accessToken = "account.accessToken"
        static let accountSession = "account.session"
        static let imageDomain = "image.domain"
        static let guestToken = "account.guestToken"
        static let guestTokenScope = "account.guestTokenScope"
        static let preferredCDNID = "player.preferredCDNID"
        static let autoplayNextEpisode = "player.autoplayNextEpisode"
        static let downloadOverCellular = "downloads.allowsCellular"
        static let useImageProxy = "image.useProxy"
        static let appProxyEnabled = "network.appProxy.enabled"
        static let appProxyConfiguration = "network.appProxy.configuration"
        static let appProxyCredentials = "network.appProxy.credentials"
        static let appNetworkRoutingMode = "network.routing.mode"
        static let appBuiltInProxyProfiles =
            "network.builtInProxy.profiles"
        static let selectedBuiltInProxyID =
            "network.builtInProxy.selectedID"
        static let deviceID = "device.id"

        static let legacyBaseURL = "server.baseURL"
        static let legacyAPIPrefix = "server.apiPrefix"
        static let legacyAccessToken = "account.accessToken"
        static let legacyPreferredCDNID = "player.preferredCDNID"
    }
}
