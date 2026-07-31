import Foundation

enum AppBuiltInProxyProfileStore {
    struct ImportResult {
        let profiles: [AppBuiltInProxyProfile]
        let importedCount: Int
        let replacedCount: Int
    }

    static func decodeProfiles(_ data: Data?) -> [AppBuiltInProxyProfile] {
        guard let data,
              let profiles = try? JSONDecoder().decode(
                [AppBuiltInProxyProfile].self,
                from: data
              ) else {
            return []
        }
        return profiles
    }

    static func importCandidates(
        _ candidates: [AppBuiltInProxyCandidate],
        into existingProfiles: [AppBuiltInProxyProfile],
        defaults: UserDefaults,
        storageKey: String
    ) throws -> ImportResult {
        var profiles = existingProfiles
        var newlyWrittenSecretRefs = [String]()
        var replacedSecretRefs = [String]()
        var replacedCount = 0

        do {
            for candidate in candidates {
                let matchingIndex = profiles.firstIndex {
                    identity(of: $0) == candidate.identity
                }
                let profileID = matchingIndex.map {
                    profiles[$0].id
                } ?? UUID()
                let secretRef = try persist(
                    candidate.secret,
                    newlyWrittenSecretRefs: &newlyWrittenSecretRefs
                )
                let profile = AppBuiltInProxyProfile(
                    id: profileID,
                    name: candidate.name,
                    kind: candidate.kind,
                    server: candidate.server,
                    port: candidate.port,
                    secretRef: secretRef,
                    skipCertificateVerification:
                        candidate.skipCertificateVerification
                )

                if let matchingIndex {
                    if let oldSecretRef = profiles[matchingIndex].secretRef {
                        replacedSecretRefs.append(oldSecretRef)
                    }
                    profiles[matchingIndex] = profile
                    replacedCount += 1
                } else {
                    profiles.append(profile)
                }
            }

            let encoded = try JSONEncoder().encode(profiles)
            defaults.set(encoded, forKey: storageKey)
        } catch {
            newlyWrittenSecretRefs.forEach(KeychainStore.remove)
            throw error
        }

        Set(replacedSecretRefs)
            .subtracting(newlyWrittenSecretRefs)
            .forEach(KeychainStore.remove)
        return ImportResult(
            profiles: profiles,
            importedCount: candidates.count,
            replacedCount: replacedCount
        )
    }

    static func remove(
        profileID: UUID,
        from existingProfiles: [AppBuiltInProxyProfile],
        defaults: UserDefaults,
        storageKey: String
    ) throws -> [AppBuiltInProxyProfile] {
        guard let profile = existingProfiles.first(where: {
            $0.id == profileID
        }) else {
            return existingProfiles
        }
        let profiles = existingProfiles.filter { $0.id != profileID }
        defaults.set(
            try JSONEncoder().encode(profiles),
            forKey: storageKey
        )
        if let secretRef = profile.secretRef {
            KeychainStore.remove(secretRef)
        }
        return profiles
    }

    static func secret(
        for profile: AppBuiltInProxyProfile
    ) throws -> AppBuiltInProxySecret {
        guard let secretRef = profile.secretRef else {
            if profile.kind.requiresSecret {
                throw AppProxyError.builtInSecretUnavailable
            }
            return .empty
        }
        guard let value = KeychainStore.string(for: secretRef),
              let data = value.data(using: .utf8),
              let secret = try? JSONDecoder().decode(
                AppBuiltInProxySecret.self,
                from: data
              ) else {
            throw AppProxyError.builtInSecretUnavailable
        }
        return secret
    }

    private static func persist(
        _ secret: AppBuiltInProxySecret,
        newlyWrittenSecretRefs: inout [String]
    ) throws -> String? {
        guard !secret.isEmpty else { return nil }
        let data = try JSONEncoder().encode(secret)
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.operationFailed(errSecDecode)
        }
        let ref = "network.builtInProxy.secret.\(UUID().uuidString)"
        try KeychainStore.setSecure(value, for: ref)
        newlyWrittenSecretRefs.append(ref)
        return ref
    }

    private static func identity(
        of profile: AppBuiltInProxyProfile
    ) -> String {
        AppBuiltInProxyCandidate(
            name: profile.name,
            kind: profile.kind,
            server: profile.server,
            port: profile.port,
            secret: .empty,
            skipCertificateVerification:
                profile.skipCertificateVerification
        ).identity
    }
}
