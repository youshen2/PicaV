import Foundation

struct VideoDownloadLocalFileResolver {
    init(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = URL(
            fileURLWithPath: NSHomeDirectory(),
            isDirectory: true
        )
    ) {
        self.fileManager = fileManager
        self.homeDirectoryURL = homeDirectoryURL
    }

    func existingURL(for persistedPath: String) -> URL? {
        guard !persistedPath.isEmpty else { return nil }

        for candidate in candidates(for: persistedPath) {
            guard fileManager.fileExists(atPath: candidate.path) else {
                continue
            }
            return candidate
        }
        return nil
    }

    static func persistedPath(
        for url: URL,
        homeDirectoryURL: URL = URL(
            fileURLWithPath: NSHomeDirectory(),
            isDirectory: true
        )
    ) -> String {
        let normalizedURL = normalized(url)
        let normalizedHomeURL = normalized(homeDirectoryURL)

        if let relativePath = relativePath(
            for: normalizedURL,
            under: normalizedHomeURL
        ) {
            return relativePath
        }

        if let relativePath = sandboxRelativePath(
            from: normalizedURL.path
        ) {
            return relativePath
        }

        return url.standardizedFileURL.path
    }

    private func candidates(for persistedPath: String) -> [URL] {
        if persistedPath.hasPrefix("/") {
            var urls = [URL(fileURLWithPath: persistedPath)]
            if let relativePath = Self.sandboxRelativePath(
                from: persistedPath
            ) {
                urls.append(
                    Self.appending(
                        relativePath,
                        to: homeDirectoryURL
                    )
                )
            }
            return urls
        }

        return [Self.appending(persistedPath, to: homeDirectoryURL)]
    }

    private static func normalized(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func relativePath(
        for url: URL,
        under directoryURL: URL
    ) -> String? {
        let directoryPath = directoryURL.path
        let prefix = directoryPath.hasSuffix("/")
            ? directoryPath
            : directoryPath + "/"
        guard url.path.hasPrefix(prefix) else { return nil }
        return String(url.path.dropFirst(prefix.count))
    }

    private static func sandboxRelativePath(
        from absolutePath: String
    ) -> String? {
        let components = URL(fileURLWithPath: absolutePath)
            .standardizedFileURL
            .pathComponents
        guard components.count >= 5 else { return nil }

        for index in 0..<(components.count - 4) where
            components[index] == "Containers"
                && components[index + 1] == "Data"
                && components[index + 2] == "Application" {
            let relativeStart = index + 4
            guard relativeStart < components.count else { return nil }
            return components[relativeStart...].joined(separator: "/")
        }
        return nil
    }

    private static func appending(
        _ relativePath: String,
        to directoryURL: URL
    ) -> URL {
        relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .reduce(directoryURL) { url, component in
                url.appendingPathComponent(String(component))
            }
            .standardizedFileURL
    }

    private let fileManager: FileManager
    private let homeDirectoryURL: URL
}
