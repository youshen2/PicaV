import Foundation
import ImageIO
import UIKit

final class AnimeImagePipeline {
    static let shared = AnimeImagePipeline()

    func image(
        for url: URL,
        proxyBaseURL: URL?,
        useProxy: Bool,
        configuration: PlatformImageConfiguration,
        maxPixelSize: CGFloat,
        networkRoute: AppNetworkRoute
    ) async throws -> UIImage {
        let cacheKeyValue = imageCacheKeyValue(
            for: url,
            configuration: configuration,
            maxPixelSize: maxPixelSize
        )
        let cacheKey = cacheKeyValue as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }
        let requestKeyValue = [
            cacheKeyValue,
            networkRoute.cacheIdentity
        ].joined(separator: "|")
        return try await requestCoordinator.image(
            for: requestKeyValue
        ) { [self] in
            try await loadImage(
                for: url,
                cacheKey: cacheKey,
                proxyBaseURL: proxyBaseURL,
                useProxy: useProxy,
                configuration: configuration,
                maxPixelSize: maxPixelSize,
                networkRoute: networkRoute
            )
        }
    }

    func cachedImage(
        for urls: [URL],
        configuration: PlatformImageConfiguration,
        maxPixelSize: CGFloat
    ) -> UIImage? {
        for url in urls {
            let key = imageCacheKeyValue(
                for: url,
                configuration: configuration,
                maxPixelSize: maxPixelSize
            ) as NSString
            if let image = imageCache.object(forKey: key) {
                return image
            }
        }
        return nil
    }

    private func loadImage(
        for url: URL,
        cacheKey: NSString,
        proxyBaseURL: URL?,
        useProxy: Bool,
        configuration: PlatformImageConfiguration,
        maxPixelSize: CGFloat,
        networkRoute: AppNetworkRoute
    ) async throws -> UIImage {
        try Task.checkCancellation()
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }
        let prefersWidthSuffix = shouldPreferWidthSuffix(
            configuration.widthSuffix,
            maxPixelSize: maxPixelSize
        )
        let diskCacheKey = [
            url.absoluteString,
            prefersWidthSuffix
                ? configuration.widthSuffix ?? ""
                : "full",
            configuration.xorKey ?? "",
            configuration.fallbackHost ?? ""
        ].joined(separator: "|")
        if url.scheme?.lowercased() != "data",
           let cachedData = await AnimeImageCacheService.cachedData(
               forKey: diskCacheKey
           ) {
            try Task.checkCancellation()
            if let image = decode(data: cachedData, maxPixelSize: maxPixelSize) {
                try Task.checkCancellation()
                imageCache.setObject(image, forKey: cacheKey, cost: imageCost(image))
                return image
            }
            await AnimeImageCacheService.remove(forKey: diskCacheKey)
        }

        try Task.checkCancellation()
        let normalizedURL = normalizedRemoteURL(
            url,
            proxyBaseURL: proxyBaseURL,
            configuration: configuration
        )
        var sources = [normalizedURL]
        if normalizedURL != url {
            sources.append(url)
        }

        var candidates: [URL] = []
        for source in sources {
            var variants = [source]
            if let suffix = configuration.widthSuffix,
               let suffixed = widthSuffixedURL(source, suffix: suffix) {
                variants = prefersWidthSuffix
                    ? [suffixed, source]
                    : [source, suffixed]
            }

            for variant in variants {
                if useProxy,
                   ["http", "https"].contains(variant.scheme?.lowercased() ?? ""),
                   let proxyBaseURL,
                   let proxyPath = configuration.proxyPath,
                   let proxyURL = imageProxyURL(
                       for: variant,
                       baseURL: proxyBaseURL,
                       path: proxyPath
                   ) {
                    candidates.append(proxyURL)
                }
                candidates.append(variant)
            }
        }
        candidates = unique(candidates)

        var lastError: Error = URLError(.cannotDecodeContentData)
        for candidate in candidates {
            do {
                try Task.checkCancellation()
                let data = try await loadData(
                    from: candidate,
                    networkRoute: networkRoute
                )
                try Task.checkCancellation()
                let decodedData = xorDecoded(data, key: configuration.xorKey)
                if let image = decode(data: decodedData, maxPixelSize: maxPixelSize) {
                    try Task.checkCancellation()
                    if url.scheme?.lowercased() != "data" {
                        await AnimeImageCacheService.store(
                            decodedData,
                            forKey: diskCacheKey
                        )
                    }
                    try Task.checkCancellation()
                    imageCache.setObject(image, forKey: cacheKey, cost: imageCost(image))
                    return image
                }
                if decodedData != data,
                   let image = decode(data: data, maxPixelSize: maxPixelSize) {
                    try Task.checkCancellation()
                    if url.scheme?.lowercased() != "data" {
                        await AnimeImageCacheService.store(
                            data,
                            forKey: diskCacheKey
                        )
                    }
                    try Task.checkCancellation()
                    imageCache.setObject(image, forKey: cacheKey, cost: imageCost(image))
                    return image
                }
                lastError = URLError(.cannotDecodeContentData)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    @MainActor
    func clear() async {
        await requestCoordinator.cancelAll()
        imageCache.removeAllObjects()
        await AnimeImageCacheService.clear()
    }

    private init() {
        imageCache.totalCostLimit = 96 * 1_024 * 1_024
        imageCache.countLimit = 180
    }

    private func loadData(
        from url: URL,
        networkRoute: AppNetworkRoute
    ) async throws -> Data {
        if url.scheme?.lowercased() == "data" {
            return try inlineImageData(from: url.absoluteString)
        }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        )
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let session = AppNetworkSessionFactory.shared.session(
            for: networkRoute,
            purpose: .image
        )
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func imageCacheKeyValue(
        for url: URL,
        configuration: PlatformImageConfiguration,
        maxPixelSize: CGFloat
    ) -> String {
        [
            url.absoluteString,
            String(Int(maxPixelSize)),
            configuration.widthSuffix ?? "",
            configuration.xorKey ?? "",
            configuration.fallbackHost ?? ""
        ].joined(separator: "|")
    }

    private func imageProxyURL(for remoteURL: URL, baseURL: URL, path: String) -> URL? {
        let endpoint = baseURL.appendingPathComponent(path)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "url", value: remoteURL.absoluteString)]
        return components.url
    }

    private func normalizedRemoteURL(
        _ url: URL,
        proxyBaseURL: URL?,
        configuration: PlatformImageConfiguration
    ) -> URL {
        let unwrapped = unwrapNestedRemoteURL(url) ?? url
        guard let fallbackHost = configuration.fallbackHost,
              let host = unwrapped.host,
              host != fallbackHost,
              !unwrapped.path.hasPrefix("/@/"),
              (
                  configuration.replaceableHostSuffixes.contains(where: host.hasSuffix)
                      || host == proxyBaseURL?.host
              ),
              var components = URLComponents(
                  url: unwrapped,
                  resolvingAgainstBaseURL: false
              ) else {
            return unwrapped
        }
        components.host = fallbackHost
        return components.url ?? unwrapped
    }

    private func unwrapNestedRemoteURL(_ url: URL) -> URL? {
        let value = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 5 else { return nil }
        let searchEnd = value.index(value.endIndex, offsetBy: -5)
        guard let range = value.range(
            of: "http",
            options: [.backwards, .caseInsensitive],
            range: value.startIndex..<searchEnd
        ), range.lowerBound > value.startIndex else {
            return nil
        }
        return URL(string: String(value[range.lowerBound...]))
    }

    private func widthSuffixedURL(_ url: URL, suffix: String) -> URL? {
        guard !suffix.isEmpty,
              url.scheme?.lowercased() != "data",
              url.pathExtension.lowercased() != "gif",
              !url.path.hasSuffix("_\(suffix)"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path += "_\(suffix)"
        return components.url
    }

    private func shouldPreferWidthSuffix(
        _ suffix: String?,
        maxPixelSize: CGFloat
    ) -> Bool {
        guard let suffix,
              let width = Double(suffix),
              width > 0 else {
            return false
        }
        return Double(maxPixelSize) <= width * 1.5
    }

    private func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    private func inlineImageData(from value: String) throws -> Data {
        guard let comma = value.firstIndex(of: ",") else {
            throw URLError(.cannotDecodeContentData)
        }
        let metadata = value[..<comma]
        let payload = String(value[value.index(after: comma)...])
        if metadata.localizedCaseInsensitiveContains(";base64") {
            guard let data = Data(base64Encoded: payload) else {
                throw URLError(.cannotDecodeContentData)
            }
            return data
        }
        guard let decoded = payload.removingPercentEncoding else {
            throw URLError(.cannotDecodeContentData)
        }
        return Data(decoded.utf8)
    }

    private func xorDecoded(_ data: Data, key keyString: String?) -> Data {
        guard let keyString else { return data }
        let key = Array(keyString.utf8)
        guard !key.isEmpty, !data.isEmpty else { return data }
        var decoded = data
        decoded.withUnsafeMutableBytes { bytes in
            guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
            for index in 0..<min(100, data.count) {
                base[index] ^= key[index % key.count]
            }
        }
        return decoded
    }

    private func decode(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 240)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private func imageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }

    private let imageCache = NSCache<NSString, UIImage>()
    private let requestCoordinator = AnimeImageRequestCoordinator()
}
