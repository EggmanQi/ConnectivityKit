import Foundation

/// 有效延迟的滑动窗口 + 加权移动平均。
/// 权重顺序：weights[0] 对应最近一次有效采样。
final class SamplingWindow {
    private let config: SamplingConfig
    private var values: [TimeInterval] = []

    init(config: SamplingConfig) {
        self.config = config
    }

    var count: Int { values.count }

    /// 追加一次有效延迟；自动裁剪到 windowSize。
    func append(_ latency: TimeInterval) {
        values.append(latency)
        if values.count > config.windowSize {
            values.removeFirst(values.count - config.windowSize)
        }
    }

    func reset() {
        values.removeAll()
    }

    /// 最近 n 次有效采样的加权平均值。
    /// 不足 windowSize 时按「最近的 min(样本数, 权重数) 项」归一化权重计算。
    var smoothed: TimeInterval? {
        guard !values.isEmpty else { return nil }
        let weights = config.weights
        let n = min(values.count, weights.count)
        guard n > 0 else { return nil }

        let recent = Array(values.suffix(n))
        let weightSlice = Array(weights.prefix(n))
        let weightSum = weightSlice.reduce(0, +)
        guard weightSum > 0 else { return recent.last }

        let weighted = zip(recent, weightSlice).reduce(0.0) { $0 + $1.0 * $1.1 }
        return weighted / weightSum
    }

    /// 判断 new 是否相对 previous 显示值达到刷新阈值（≥ms 或 ≥ratio，取大）。
    func shouldRefresh(previous: TimeInterval?, new: TimeInterval) -> Bool {
        guard let previous = previous else { return true }
        let diff = abs(new - previous)
        let ratio = previous > 0 ? diff / previous : diff
        let exceedsMs = diff >= config.displayThresholdMs
        let exceedsRatio = ratio >= config.displayThresholdRatio
        // 两个阈值取「更大者」才生效，即 OR 语义。
        return exceedsMs || exceedsRatio
    }
}
