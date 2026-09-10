import Foundation

/// 默认历史存储：仅内存，先进先出。所有环境通用。
public final class InMemoryHistoryStore: ConnectivityHistoryStoring {
    private let queue = DispatchQueue(label: "connectivitykit.history.memory")
    private var entries: [ConnectivityHistoryEntry] = []
    public let maxEntries: Int

    public init(maxEntries: Int = 2000) {
        self.maxEntries = max(1, maxEntries)
    }

    public func append(_ entry: ConnectivityHistoryEntry) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    public func entries(limit: Int) -> [ConnectivityHistoryEntry] {
        queue.sync {
            let n = min(max(0, limit), entries.count)
            return Array(entries.suffix(n))
        }
    }

    public func clear() {
        queue.async { [weak self] in
            self?.entries.removeAll()
        }
    }
}

/// 文件历史存储：Debug 宿主接线注入以启用持久化。
/// 存于 Caches（不入 iCloud/备份），JSON，滚动裁剪。
public final class FileHistoryStore: ConnectivityHistoryStoring {
    private let queue = DispatchQueue(label: "connectivitykit.history.file")
    private let fileURL: URL
    private var entries: [ConnectivityHistoryEntry] = []
    public let maxEntries: Int

    public init(directoryURL: URL, maxEntries: Int = 2000) throws {
        self.maxEntries = max(1, maxEntries)
        self.fileURL = directoryURL.appendingPathComponent("connectivity_history.json")
        try FileManager.default.createDirectory(at: directoryURL,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
        load()
    }

    /// Caches 目录下的便捷初始化。
    public convenience init(maxEntries: Int = 2000) throws {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        try self.init(directoryURL: caches, maxEntries: maxEntries)
    }

    public func append(_ entry: ConnectivityHistoryEntry) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.entries.append(entry)
            self.trimIfNeeded()
            self.persist()
        }
    }

    public func entries(limit: Int) -> [ConnectivityHistoryEntry] {
        queue.sync {
            let n = min(max(0, limit), entries.count)
            return Array(entries.suffix(n))
        }
    }

    public func clear() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.entries.removeAll()
            try? FileManager.default.removeItem(at: self.fileURL)
        }
    }

    // MARK: - Private

    private func trimIfNeeded() {
        guard entries.count > maxEntries else { return }
        entries.removeFirst(entries.count - maxEntries)
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([ConnectivityHistoryEntry].self, from: data)) ?? []
    }
}
