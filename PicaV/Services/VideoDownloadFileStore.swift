import Foundation

struct VideoDownloadOutput: Sendable {
    let temporaryURL: URL
    let destinationURL: URL
}

actor VideoDownloadFileStore {
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func prepareOutput(for item: VideoDownloadItem) throws
        -> VideoDownloadOutput {
        let root = try downloadsDirectory()
        let itemDirectory = root.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: itemDirectory,
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = itemDirectory
        try? mutableDirectory.setResourceValues(values)

        let filename = Self.filename(for: item)
        return VideoDownloadOutput(
            temporaryURL: itemDirectory.appendingPathComponent(
                filename + ".partial.mp4"
            ),
            destinationURL: itemDirectory.appendingPathComponent(
                filename + ".mp4"
            )
        )
    }

    func remove(_ urls: [URL]) {
        for url in urls {
            guard !Task.isCancelled else { return }
            try? fileManager.removeItem(at: url)
            removeEmptyDownloadDirectory(containing: url)
        }
    }

    private func downloadsDirectory() throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent(
            "VideoDownloads",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func removeEmptyDownloadDirectory(containing url: URL) {
        guard let root = try? downloadsDirectory() else { return }
        let directory = url.deletingLastPathComponent().standardizedFileURL
        let rootPath = root.standardizedFileURL.path + "/"
        guard directory.path.hasPrefix(rootPath),
              (try? fileManager.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil
              ).isEmpty) == true else {
            return
        }
        try? fileManager.removeItem(at: directory)
    }

    private static func filename(for item: VideoDownloadItem) -> String {
        let raw = "\(item.anime.title) - \(item.episodeTitle)"
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let sanitized = raw.components(separatedBy: invalid)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = sanitized.isEmpty ? "PicaV 视频" : sanitized
        return String(fallback.prefix(100))
    }

    private let fileManager: FileManager
}
