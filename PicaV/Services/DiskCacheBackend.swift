import CryptoKit
import Foundation

actor DiskCacheBackend {
    init(
        directoryName: String,
        fileExtension: String? = nil,
        minimumCapacityBytes: Int,
        initialCapacityBytes: Int
    ) {
        let root = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        directoryURL = root.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
        self.fileExtension = fileExtension
        self.minimumCapacityBytes = minimumCapacityBytes
        capacityBytes = max(initialCapacityBytes, minimumCapacityBytes)
    }

    func configure(
        capacityBytes: Int,
        generation: Int
    ) {
        guard generation >= configurationGeneration else { return }
        configurationGeneration = generation
        self.capacityBytes = max(
            capacityBytes,
            minimumCapacityBytes
        )
        prepareDirectory()
        trimTask?.cancel()
        trimTask = nil
        trimIfNeeded()
    }

    func clear() {
        trimTask?.cancel()
        trimTask = nil
        try? fileManager.removeItem(at: directoryURL)
        prepareDirectory()
    }

    func usageBytes() -> Int {
        Int(min(diskUsage(), Int64(Int.max)))
    }

    func data(
        forKey key: String,
        validator: (Data) -> Bool = { !$0.isEmpty }
    ) -> Data? {
        guard !Task.isCancelled else { return nil }
        let fileURL = cacheFileURL(forKey: key)
        guard let data = try? Data(contentsOf: fileURL) else {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        guard !Task.isCancelled else { return nil }
        guard validator(data) else {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        touch(fileURL)
        return data
    }

    func store(
        _ data: Data,
        forKey key: String,
        validator: (Data) -> Bool = { !$0.isEmpty }
    ) {
        guard !Task.isCancelled, validator(data) else { return }
        prepareDirectory()
        let fileURL = cacheFileURL(forKey: key)
        do {
            try data.write(to: fileURL, options: [.atomic])
            touch(fileURL)
            scheduleTrim()
        } catch {
            return
        }
    }

    func value<Value: Decodable>(
        forKey key: String,
        as type: Value.Type,
        validator: (Value) -> Bool
    ) -> Value? {
        guard let data = data(forKey: key) else { return nil }
        guard !Task.isCancelled else { return nil }
        guard let value = try? JSONDecoder().decode(type, from: data),
              validator(value) else {
            remove(forKey: key)
            return nil
        }
        return value
    }

    func store<Value: Encodable>(
        _ value: Value,
        forKey key: String
    ) {
        guard !Task.isCancelled,
              let data = try? JSONEncoder().encode(value) else {
            return
        }
        store(data, forKey: key)
    }

    func remove(forKey key: String) {
        try? fileManager.removeItem(at: cacheFileURL(forKey: key))
    }

    private func scheduleTrim() {
        guard trimTask == nil else { return }
        trimTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await self?.runScheduledTrim()
        }
    }

    private func runScheduledTrim() {
        trimTask = nil
        trimIfNeeded()
    }

    private func prepareDirectory() {
        try? fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func cacheFileURL(forKey key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        if let fileExtension {
            return directoryURL.appendingPathComponent(
                "\(digest).\(fileExtension)",
                isDirectory: false
            )
        }
        return directoryURL.appendingPathComponent(
            digest,
            isDirectory: false
        )
    }

    private func touch(_ fileURL: URL) {
        try? fileManager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )
    }

    private func trimIfNeeded() {
        guard !Task.isCancelled else { return }
        let files = cacheFiles()
        var totalBytes = files.reduce(Int64(0)) { $0 + $1.byteCount }
        guard totalBytes > Int64(capacityBytes) else { return }

        for file in files.sorted(by: { $0.modifiedAt < $1.modifiedAt }) {
            guard !Task.isCancelled else { return }
            try? fileManager.removeItem(at: file.url)
            totalBytes -= file.byteCount
            if totalBytes <= Int64(capacityBytes) {
                break
            }
        }
    }

    private func diskUsage() -> Int64 {
        cacheFiles().reduce(Int64(0)) { $0 + $1.byteCount }
    }

    private func cacheFiles() -> [CacheFile] {
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey
        ]
        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                return nil
            }
            return CacheFile(
                url: url,
                byteCount: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }
    }

    private struct CacheFile {
        let url: URL
        let byteCount: Int64
        let modifiedAt: Date
    }

    private let directoryURL: URL
    private let fileExtension: String?
    private let minimumCapacityBytes: Int
    private let fileManager = FileManager.default
    private var capacityBytes: Int
    private var configurationGeneration = 0
    private var trimTask: Task<Void, Never>?
}
