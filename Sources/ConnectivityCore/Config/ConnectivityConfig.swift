import Foundation

// MARK: - 探针目标

/// 一次探测的目标。正式环境通常指向 Base URL 根路径或一个轻量健康接口。
public struct ProbeTarget {
    public let url: URL
    public let method: String
    public let timeout: TimeInterval
    public let headers: [String: String]

    public init(url: URL,
                method: String = "GET",
                timeout: TimeInterval = 5,
                headers: [String: String] = [:]) {
        self.url = url
        self.method = method
        self.timeout = timeout
        self.headers = headers
    }
}

// MARK: - 加权平滑配置

public struct SamplingConfig {
    /// 有效样本窗口大小（取最近 N 次）
    public var windowSize: Int
    /// 权重，index 0 对应最近一次采样
    public var weights: [Double]
    /// 显示刷新阈值：与当前显示值的偏差达到该毫秒数时刷新
    public var displayThresholdMs: Double
    /// 显示刷新阈值：与当前显示值的偏差达到该比例时刷新
    public var displayThresholdRatio: Double

    public init(windowSize: Int = 3,
                weights: [Double] = [0.5, 0.3, 0.2],
                displayThresholdMs: Double = 20,
                displayThresholdRatio: Double = 0.1) {
        self.windowSize = max(1, windowSize)
        self.weights = weights
        self.displayThresholdMs = displayThresholdMs
        self.displayThresholdRatio = displayThresholdRatio
    }
}

// MARK: - 档位阈值

public struct QualityBands {
    /// excellent 上限（毫秒）
    public var excellentMaxMs: Double = 150
    /// good 上限（毫秒）
    public var goodMaxMs: Double = 300
    /// fair 上限（毫秒）
    public var fairMaxMs: Double = 600

    public init() {}

    public func level(forLatencyMs ms: Double) -> SignalLevel {
        if ms < excellentMaxMs { return .excellent }
        if ms < goodMaxMs { return .good }
        if ms < fairMaxMs { return .fair }
        return .poor
    }
}

// MARK: - 总配置

public struct ConnectivityConfig {
    /// 前台轮询间隔（秒）
    public var probeInterval: TimeInterval = 30
    /// 后台停留超过该时长视为「久后台」，回前台需重建采样窗口
    public var backgroundPauseThreshold: TimeInterval = 10
    /// 主探针目标
    public var target: ProbeTarget
    /// 附加探针目标（多探针场景），结果与主探针合并
    public var additionalTargets: [ProbeTarget] = []
    /// 加权平滑与显示阈值
    public var sampling: SamplingConfig = SamplingConfig()
    /// 档位阈值
    public var qualityBands: QualityBands = QualityBands()
    /// 档位升降滞回所需的连续采样数
    public var hysteresisRequiredConsecutive: Int = 3
    /// 网络类型变化时是否立即补测
    public var probeOnNetworkChange: Bool = true
    /// 网络类型变化时是否清零连续失败计数
    public var resetFailuresOnNetworkChange: Bool = true
    /// 网络恢复 / 回前台时是否重建采样窗口（丢弃旧样本）
    public var rebuildWindowOnRecovery: Bool = true
    /// 手动刷新后距下次自动探测的间隔重置为完整 probeInterval
    public var resetTimerOnManualRefresh: Bool = true

    public init(target: ProbeTarget) {
        self.target = target
    }
}
