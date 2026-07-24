import Combine
import Foundation

final class AppSettings: ObservableObject {
    static let defaultBaseURL = AnimePlatformRegistry.defaultAdapter.defaultBaseURL
    static let defaultAPIPrefix = AnimePlatformRegistry.defaultAdapter.defaultAPIPrefix

    @Published private(set) var platformID: AnimePlatformID

    @Published var baseURLText: String {
        didSet {
            defaults.set(baseURLText, forKey: scopedKey(Keys.baseURL))
            invalidateGuestSession()
        }
    }

    @Published var apiPrefix: String {
        didSet {
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

    @Published var useImageProxy: Bool {
        didSet { defaults.set(useImageProxy, forKey: Keys.useImageProxy) }
    }

    @Published private(set) var guestSessionActive: Bool

    let deviceID: String
    let requestSID: String

    var activePlatform: AnimePlatformAdapter {
        AnimePlatformRegistry.adapter(for: platformID)
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
        let platform = AnimePlatformRegistry.adapter(for: selectedPlatform)
        let platformKey: (String) -> String = {
            Self.scopedKey($0, platformID: selectedPlatform)
        }

        platformID = selectedPlatform
        baseURLText = defaults.string(forKey: platformKey(Keys.baseURL))
            ?? defaults.string(forKey: Keys.legacyBaseURL)
            ?? platform.defaultBaseURL
        apiPrefix = defaults.string(forKey: platformKey(Keys.apiPrefix))
            ?? defaults.string(forKey: Keys.legacyAPIPrefix)
            ?? platform.defaultAPIPrefix
        let scopedAccessToken = KeychainStore.string(for: platformKey(Keys.accessToken))
        accessToken = scopedAccessToken
            ?? KeychainStore.string(for: Keys.legacyAccessToken)
            ?? ""
        accountSession = Self.decodeSession(
            defaults.data(forKey: platformKey(Keys.accountSession))
        )
        imageDomain = defaults.string(forKey: platformKey(Keys.imageDomain)) ?? ""
        preferredCDNID = defaults.string(forKey: platformKey(Keys.preferredCDNID))
            ?? defaults.string(forKey: Keys.legacyPreferredCDNID)
            ?? ""
        guestToken = ""
        guestSessionActive = false
        requestSID = Self.randomHex(length: 32)

        if defaults.object(forKey: Keys.autoplayNextEpisode) == nil {
            autoplayNextEpisode = true
        } else {
            autoplayNextEpisode = defaults.bool(forKey: Keys.autoplayNextEpisode)
        }

        if defaults.object(forKey: Keys.useImageProxy) == nil {
            useImageProxy = true
        } else {
            useImageProxy = defaults.bool(forKey: Keys.useImageProxy)
        }

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

        if scopedAccessToken == nil, !accessToken.isEmpty {
            KeychainStore.set(accessToken, for: platformKey(Keys.accessToken))
            KeychainStore.remove(Keys.legacyAccessToken)
        }
    }

    func selectPlatform(_ id: AnimePlatformID) {
        guard id != platformID else { return }
        invalidateGuestSession()

        platformID = id
        defaults.set(id.rawValue, forKey: Keys.platformID)
        let platform = activePlatform
        baseURLText = defaults.string(forKey: scopedKey(Keys.baseURL))
            ?? platform.defaultBaseURL
        apiPrefix = defaults.string(forKey: scopedKey(Keys.apiPrefix))
            ?? platform.defaultAPIPrefix
        accessToken = KeychainStore.string(for: scopedKey(Keys.accessToken)) ?? ""
        accountSession = Self.decodeSession(
            defaults.data(forKey: scopedKey(Keys.accountSession))
        )
        imageDomain = defaults.string(forKey: scopedKey(Keys.imageDomain)) ?? ""
        preferredCDNID = defaults.string(forKey: scopedKey(Keys.preferredCDNID)) ?? ""
    }

    func restoreServerDefaults() {
        baseURLText = activePlatform.defaultBaseURL
        apiPrefix = activePlatform.defaultAPIPrefix
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
        accessToken = ""
        accountSession = nil
        defaults.removeObject(forKey: scopedKey(Keys.accountSession))
        invalidateGuestSession()
    }

    func setGuestToken(_ token: String) {
        guard !token.isEmpty else { return }
        guestToken = token
        KeychainStore.set(token, for: Keys.guestToken)
        defaults.set(sessionScope, forKey: Keys.guestTokenScope)
        guestSessionActive = true
    }

    func invalidateGuestSession() {
        guestToken = ""
        KeychainStore.remove(Keys.guestToken)
        defaults.removeObject(forKey: Keys.guestTokenScope)
        guestSessionActive = false
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
        static let useImageProxy = "image.useProxy"
        static let deviceID = "device.id"

        static let legacyBaseURL = "server.baseURL"
        static let legacyAPIPrefix = "server.apiPrefix"
        static let legacyAccessToken = "account.accessToken"
        static let legacyPreferredCDNID = "player.preferredCDNID"
    }
}
