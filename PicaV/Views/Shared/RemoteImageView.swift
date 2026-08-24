import Combine
import SwiftUI
import UIKit

struct RemoteImageView: View {
    @EnvironmentObject private var settings: RemoteImageSettings
    @StateObject private var loader = RemoteImageLoader()

    private let urls: [URL]
    private let maxPixelSize: CGFloat
    private let contentMode: ContentMode
    private let backgroundColor: Color

    init(
        url: URL?,
        maxPixelSize: CGFloat = 900,
        contentMode: ContentMode = .fill,
        backgroundColor: Color = Color(UIColor.secondarySystemFill)
    ) {
        urls = url.map { [$0] } ?? []
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
        self.backgroundColor = backgroundColor
    }

    init(
        urls: [URL?],
        maxPixelSize: CGFloat = 900,
        contentMode: ContentMode = .fill,
        backgroundColor: Color = Color(UIColor.secondarySystemFill)
    ) {
        var seen = Set<String>()
        self.urls = urls.compactMap { $0 }.filter {
            seen.insert($0.absoluteString).inserted
        }
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
        self.backgroundColor = backgroundColor
    }

    var body: some View {
        ZStack {
            backgroundColor

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
            let contentKey = contentID
            guard let networkRoute = try? settings.networkRoute() else {
                loader.reset()
                return
            }
            await loader.load(
                requestKey: requestKey,
                contentKey: contentKey,
                urls: urls,
                proxyBaseURL: settings.apiBaseURL,
                useProxy: settings.useImageProxy,
                configuration: settings.imageConfiguration,
                maxPixelSize: maxPixelSize,
                networkRoute: networkRoute
            )
        }
    }

    private var displayedImage: UIImage? {
        loader.image(forContentKey: contentID)
            ?? AnimeImagePipeline.shared.cachedImage(
                for: urls,
                configuration: settings.imageConfiguration,
                maxPixelSize: maxPixelSize
            )
    }

    private var contentID: String {
        [
            urls.map(\.absoluteString).joined(separator: ","),
            String(Int(maxPixelSize)),
            settings.platformID.rawValue
        ].joined(separator: "|")
    }

    private var taskID: String {
        [
            contentID,
            String(settings.useImageProxy),
            settings.apiBaseURL.absoluteString,
            String(settings.routeRevision),
            String(settings.revision)
        ].joined(separator: "|")
    }
}

@MainActor
private final class RemoteImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var isLoading = false

    func load(
        requestKey: String,
        contentKey: String,
        urls: [URL],
        proxyBaseURL: URL,
        useProxy: Bool,
        configuration: PlatformImageConfiguration,
        maxPixelSize: CGFloat,
        networkRoute: AppNetworkRoute
    ) async {
        guard !urls.isEmpty else {
            image = nil
            currentContentKey = nil
            currentRequestKey = nil
            isLoading = false
            return
        }

        if currentContentKey != contentKey {
            image = nil
            currentContentKey = contentKey
        }
        currentRequestKey = requestKey
        if image != nil {
            isLoading = false
            return
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
            if currentRequestKey == requestKey {
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
                      currentRequestKey == requestKey,
                      currentContentKey == contentKey else {
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
        if currentRequestKey == requestKey,
           currentContentKey == contentKey {
            image = nil
        }
    }

    func image(forContentKey contentKey: String) -> UIImage? {
        currentContentKey == contentKey ? image : nil
    }

    func reset() {
        image = nil
        currentContentKey = nil
        currentRequestKey = nil
        isLoading = false
    }

    private var currentContentKey: String?
    private var currentRequestKey: String?
}
