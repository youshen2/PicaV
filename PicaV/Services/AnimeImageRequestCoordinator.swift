import Foundation
import UIKit

actor AnimeImageRequestCoordinator {
    func image(
        for key: String,
        loader: @escaping () async throws -> UIImage
    ) async throws -> UIImage {
        let waiterID = UUID()
        let task: Task<UIImage, Error>
        if var entry = entries[key] {
            entry.waiters.insert(waiterID)
            entries[key] = entry
            task = entry.task
        } else {
            task = Task(priority: .userInitiated) {
                try await loader()
            }
            entries[key] = Entry(
                task: task,
                waiters: [waiterID]
            )
        }

        defer {
            finishWaiter(waiterID, for: key)
        }
        return try await withTaskCancellationHandler {
            do {
                let image = try await task.value
                try Task.checkCancellation()
                return image
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(waiterID, for: key)
            }
        }
    }

    func cancelAll() {
        entries.values.forEach { $0.task.cancel() }
        entries.removeAll()
    }

    private func cancelWaiter(_ waiterID: UUID, for key: String) {
        guard var entry = entries[key] else { return }
        entry.waiters.remove(waiterID)
        if entry.waiters.isEmpty {
            entry.task.cancel()
            entries[key] = nil
        } else {
            entries[key] = entry
        }
    }

    private func finishWaiter(_ waiterID: UUID, for key: String) {
        guard var entry = entries[key] else { return }
        entry.waiters.remove(waiterID)
        entries[key] = entry.waiters.isEmpty ? nil : entry
    }

    private struct Entry {
        let task: Task<UIImage, Error>
        var waiters: Set<UUID>
    }

    private var entries: [String: Entry] = [:]
}
