import Foundation

/// 一条历史记录（用于调试展示，Debug 宿主可持久化）。
public struct ConnectivityHistoryEntry: Codable {
    public let timestamp: Date
    public let targetURL: String
    /// 平滑后的延迟毫秒（可达且有效时）
    public let smoothedLatencyMs: Double?
    /// 最近一次原始延迟毫秒（可达时）
    public let rawLatencyMs: Double?
    public let httpStatusCode: Int?
    public let errorKind: String?
    public let signalLevelRaw: Int
    public let reachable: Bool

    public init(timestamp: Date,
                targetURL: String,
                smoothedLatencyMs: Double?,
                rawLatencyMs: Double?,
                httpStatusCode: Int?,
                errorKind: String?,
                signalLevelRaw: Int,
                reachable: Bool) {
        self.timestamp = timestamp
        self.targetURL = targetURL
        self.smoothedLatencyMs = smoothedLatencyMs
        self.rawLatencyMs = rawLatencyMs
        self.httpStatusCode = httpStatusCode
        self.errorKind = errorKind
        self.signalLevelRaw = signalLevelRaw
        self.reachable = reachable
    }
}

/// 历史存储抽象。核心只依赖协议：
/// - 内存实现：所有环境通用（默认）；
/// - 文件实现：仅由 Debug 宿主接线注入，实现「仅 Debug 持久化」。
public protocol ConnectivityHistoryStoring: AnyObject {
    func append(_ entry: ConnectivityHistoryEntry)
    func entries(limit: Int) -> [ConnectivityHistoryEntry]
    func clear()
}
