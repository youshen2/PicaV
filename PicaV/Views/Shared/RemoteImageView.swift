import Combine
import SwiftUI
import UIKit

struct RemoteImageView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var loader = RemoteImageLoader()

    private let urls: [URL]
    private let maxPixelSize: CGFloat
    private let contentMode: ContentMode

    init(
        url: URL?,
        maxPixelSize: CGFloat = 900,
        contentMode: ContentMode = .fill
    ) {
        urls = url.map { [$0] } ?? []
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
    }

    init(
        urls: [URL?],
        maxPixelSize: CGFloat = 900,
        contentMode: ContentMode = .fill
    ) {
        var seen = Set<String>()
        self.urls = urls.compactMap { $0 }.filter {
            seen.insert($0.absoluteString).inserted
        }
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
    }

    var body: some View {
        ZStack {
            Color(.secondarySystemFill)

            if let image = displayedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if loader.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .clipped()
        .task(id: taskID) {
            let requestKey = taskID
            guard let networkRoute = try? settings.appNetworkRoute() else {
                loader.reset()
                return
            }
            await loader.load(
                requestKey: requestKey,
                urls: urls,
                proxyBaseURL: settings.apiBaseURL,
                useProxy: settings.useImageProxy,
                configuration: settings.activePlatform.imageConfiguration,
                maxPixelSize: maxPixelSize,
                networkRoute: networkRoute
            )
        }
    }

    private var displayedImage: UIImage? {
        loader.image(for: taskID)
            ?? AnimeImagePipeline.shared.cachedImage(
                for: urls,
                configuration: settings.activePlatform.imageConfiguration,
                maxPixelSize: maxPixelSize
            )
    }

    private var taskID: String {
        [
            urls.map(\.absoluteString).joined(separator: ","),
            String(Int(maxPixelSize)),
            String(settings.useImageProxy),
            settings.apiBaseURL.absoluteString,
            settings.platformID.rawValue,
            String(settings.appProxyRevision)
        ].joined(separator: "|")
    }
}

@MainActor
private final class RemoteImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var isLoading = false

    func load(
        requestKey: String,
        urls: [URL],
        proxyBaseURL: URL,
        useProxy: Bool,
        configuration: PlatformImageConfiguration,
        maxPixelSize: CGFloat,
        networkRoute: AppNetworkRoute
    ) async {
        guard !urls.isEmpty else {
            image = nil
            currentKey = nil
            isLoading = false
            return
        }

        if currentKey == requestKey, image != nil {
            isLoading = false
            return
        }
        if currentKey != requestKey {
            image = nil
            currentKey = requestKey
        }
        if let cachedImage = AnimeImagePipeline.shared.cachedImage(
            for: urls,
            configuration: configuration,
            maxPixelSize: maxPixelSize
        ) {
            image = cachedImage
            isLoading = false
            return
        }
        isLoading = true
        defer {
            if currentKey == requestKey {
                isLoading = false
            }
        }
        for url in urls {
            do {
                let loaded = try await AnimeImagePipeline.shared.image(
                    for: url,
                    proxyBaseURL: proxyBaseURL,
                    useProxy: useProxy,
                    configuration: configuration,
                    maxPixelSize: maxPixelSize,
                    networkRoute: networkRoute
                )
                guard !Task.isCancelled,
                      currentKey == requestKey else {
                    return
                }
                withAnimation(.easeOut(duration: 0.18)) {
                    image = loaded
                }
                return
            } catch {
                guard !Task.isCancelled else { return }
            }
        }
        if currentKey == requestKey {
            image = nil
        }
    }

    func image(for requestKey: String) -> UIImage? {
        currentKey == requestKey ? image : nil
    }

    func reset() {
        image = nil
        currentKey = nil
        isLoading = false
    }

    private var currentKey: String?
}
