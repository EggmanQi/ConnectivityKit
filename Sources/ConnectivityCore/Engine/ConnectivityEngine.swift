import Foundation

// MARK: - 对外模型

/// 引擎运行状态
public enum ConnectivityEngineState: Equatable {
    case idle      // 未启动 / 已停止
    case running   // 运行中（含离线时等待网络恢复）
    case paused    // 后台挂起
}

/// 每次状态变化 / 采样后对外发布的快照
public struct ConnectivitySnapshot: Equatable {
    public let timestamp: Date
    public let engineState: ConnectivityEngineState
    public let pathState: NetworkPathState
    public let reachable: Bool
    public let signalLevel: SignalLevel
    /// 平滑后并已通过显示阈值的延迟（毫秒）
    public let smoothedLatencyMs: Double?
    public let httpStatusCode: Int?
    public let probeErrorKind: ProbeErrorKind?
    public let consecutiveFailures: Int
    /// 滞回统计（调试用）
    public let pendingLevel: SignalLevel?
    public let pendingStreak: Int
    /// 是否正在探测（用于 UI 的 loading 态）
    public let isProbing: Bool
}

// MARK: - 引擎

/// 网络质量探测引擎。
/// - 轮询：前台按配置间隔由重复定时器驱动；手动刷新立即探测并可重置计时；
/// - 前后台：`handleAppDidEnterBackground/BecomeActive` 由宿主生命周期桥调用，
///   后台即挂起；后台停留超过阈值则回前台时重建采样窗口并补测；
/// - 网络切换：内部 NWPathMonitor 监听；离线停表并置不可达，
///   恢复 / 换网立即补测并可清零连续失败计数；
/// - 线程：内部串行队列执行，`onUpdate` 回调主线程，读取方法线程安全。
public final class ConnectivityEngine {

    public private(set) var config: ConnectivityConfig?
    public private(set) var engineState: ConnectivityEngineState = .idle

    /// 历史存储（可选注入）。Debug 宿主可注入文件实现以持久化。
    public var historyStore: ConnectivityHistoryStoring?

    /// 主线程回调：每次对外可见状态变化时触发。
    public var onUpdate: ((ConnectivitySnapshot) -> Void)?

    // MARK: 内部状态

    private let queue = DispatchQueue(label: "connectivitykit.engine")
    private let probe = HTTPProbe()
    private let monitor = ConnectivityNetworkMonitor()

    private var configRef: ConnectivityConfig?
    private var samplingWindow = SamplingWindow(config: SamplingConfig())
    private var gate = LevelGate(requiredConsecutive: 3)
    private var displayedSmoothedMs: Double?

    private var reachable = true
    private var lastPathState: NetworkPathState = .unknown
    private var consecutiveFailures = 0
    private var lastHttpStatus: Int?
    private var lastProbeError: ProbeErrorKind?

    private var recentSamples: [ProbeSample] = []
    private var probeTimer: DispatchSourceTimer?
    private var probeInFlight = false

    private var backgrounded = false
    private var lastBackgroundDate: Date = Date()
    private var latest = ConnectivitySnapshot.makeInitial()

    public init() {}

    deinit {
        probeTimer?.cancel()
        monitor.stop()
    }

    // MARK: - 生命周期控制

    /// 启动（幂等）：已运行时按新配置重启。
    public func start(config: ConnectivityConfig) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.teardownInternal()
            self.config = config
            self.configRef = config
            self.samplingWindow = SamplingWindow(config: config.sampling)
            self.gate = LevelGate(requiredConsecutive: config.hysteresisRequiredConsecutive)
            self.reachable = true
            self.lastPathState = .unknown
            self.engineState = .running
            self.publish()

            self.monitor.onStatusChange = { [weak self] state in
                self?.handlePathState(state)
            }
            self.monitor.start()

            // 立即探测一次；重复定时器从此刻起按间隔运转。
            self.performProbe()
            self.restartTimer(delay: config.probeInterval)
        }
    }

    /// 停止：取消定时器与网络监听，保留历史存储内容。
    public func stop() {
        queue.async { [weak self] in
            self?.teardownInternal()
        }
    }

    /// 手动立即探测一次（可选重置轮询计时）。
    public func refreshNow() {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.engineState == .running, !self.probeInFlight else { return }
            if self.config?.resetTimerOnManualRefresh ?? true {
                self.restartTimer(delay: self.config?.probeInterval ?? 30)
            }
            self.performProbe()
        }
    }

    /// 运行时调整轮询间隔（秒）。下限由配置/调用方保证，至少 1s。
    /// 运行中会立即按新间隔重建定时器。
    public func setProbeInterval(_ interval: TimeInterval) {
        queue.async { [weak self] in
            guard let self = self, var cfg = self.configRef else { return }
            let clamped = max(1, interval)
            guard clamped != cfg.probeInterval else { return }
            cfg.probeInterval = clamped
            self.config = cfg
            self.configRef = cfg
            if self.engineState == .running {
                self.restartTimer(delay: clamped)
                self.publish()
            }
        }
    }

    /// 宿主生命周期：进入后台。立即挂起探测以省电；
    /// 若后台停留超过配置阈值，回前台时重建采样窗口并补测。
    public func handleAppDidEnterBackground(at date: Date = Date()) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.engineState == .running || self.engineState == .paused else { return }
            self.backgrounded = true
            self.lastBackgroundDate = date
            self.engineState = .paused
            self.cancelTimer()
            self.publish()
        }
    }

    /// 宿主生命周期：回到前台。
    public func handleAppDidBecomeActive(at date: Date = Date()) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.engineState == .paused else { return }
            self.backgrounded = false
            let gap = date.timeIntervalSince(self.lastBackgroundDate)
            let threshold = self.config?.backgroundPauseThreshold ?? 10
            if gap >= threshold {
                self.resetAnalysis()
            }
            self.engineState = .running
            self.publish()
            // 回前台立即补测一次并重建轮询计时。
            if !self.probeInFlight {
                self.performProbe()
                self.restartTimer(delay: self.config?.probeInterval ?? 30)
            }
        }
    }

    // MARK: - 读取

    public func currentSnapshot() -> ConnectivitySnapshot {
        queue.sync { latest }
    }

    /// 最近 N 条原始采样（新→旧）。
    public func recentRawSamples(limit: Int = 50) -> [ProbeSample] {
        queue.sync {
            let n = min(max(0, limit), recentSamples.count)
            return Array(recentSamples.suffix(n).reversed())
        }
    }

    // MARK: - 内部：探测

    private func performProbe() {
        guard engineState == .running,
              !probeInFlight,
              reachable,
              let target = configRef?.target else { return }

        probeInFlight = true
        publish() // 对外广播「探测中」，供 UI 进入 loading 态
        let cfg = configRef
        probe.probe(target) { [weak self] sample in
            self?.queue.async {
                guard let self = self else { return }
                self.probeInFlight = false
                self.handleSample(sample, cfg: cfg)
            }
        }

        // 多探针：附加目标并行探测，仅记录。
        for extra in cfg?.additionalTargets ?? [] {
            probe.probe(extra) { [weak self] sample in
                self?.queue.async {
                    self?.handleSample(sample, cfg: cfg, isExtra: true)
                }
            }
        }
    }

    private func handleSample(_ sample: ProbeSample, cfg: ConnectivityConfig?, isExtra: Bool = false) {
        if sample.errorKind == .cancelled { return }
        recordRecent(sample)

        if sample.serverReachable, let latency = sample.latency, let cfg = cfg {
            consecutiveFailures = 0
            lastHttpStatus = sample.httpStatusCode
            lastProbeError = nil

            if !isExtra {
                samplingWindow.append(latency)
                appendHistory(sample: sample, cfg: cfg)

                let smoothedMs = (samplingWindow.smoothed ?? latency) * 1000
                let candidate = cfg.qualityBands.level(forLatencyMs: smoothedMs)
                gate.update(candidate: candidate)

                if samplingWindow.shouldRefresh(previous: displayedSmoothedMs, new: smoothedMs) {
                    displayedSmoothedMs = smoothedMs
                }
            }
        } else if let error = sample.errorKind, error != .cancelled {
            consecutiveFailures += 1
            lastHttpStatus = sample.httpStatusCode
            lastProbeError = error
        }
        publish()
    }

    private func recordRecent(_ sample: ProbeSample) {
        recentSamples.append(sample)
        if recentSamples.count > 30 {
            recentSamples.removeFirst(recentSamples.count - 30)
        }
    }

    private func appendHistory(sample: ProbeSample, cfg: ConnectivityConfig) {
        guard let store = historyStore else { return }
        let smoothedMs = (samplingWindow.smoothed ?? sample.latency ?? 0) * 1000
        let entry = ConnectivityHistoryEntry(timestamp: sample.timestamp,
                                             targetURL: sample.targetURL.absoluteString,
                                             smoothedLatencyMs: smoothedMs,
                                             rawLatencyMs: (sample.latency ?? 0) * 1000,
                                             httpStatusCode: sample.httpStatusCode,
                                             errorKind: sample.errorKind?.rawValue,
                                             signalLevelRaw: gate.confirmed.rawValue,
                                             reachable: sample.serverReachable)
        store.append(entry)
    }

    // MARK: - 内部：网络切换

    private func handlePathState(_ state: NetworkPathState) {
        let old = lastPathState
        lastPathState = state

        let cfg = configRef

        // 离线：停表、置不可达，保留连续失败计数。
        if state == .offline {
            reachable = false
            lastProbeError = .cannotConnect
            lastHttpStatus = nil
            cancelTimer()
            publish()
            return
        }

        let recoveredFromOffline = old == .offline
        let typeChanged = old != .unknown && old != .offline && old != state
        let meaningfulChange = recoveredFromOffline || typeChanged

        if meaningfulChange {
            if recoveredFromOffline {
                reachable = true
                if cfg?.rebuildWindowOnRecovery ?? true {
                    resetAnalysis()
                }
            }
            if cfg?.resetFailuresOnNetworkChange ?? true {
                consecutiveFailures = 0
                lastProbeError = nil
                lastHttpStatus = nil
            }
            publish()

            // 恢复 / 换网立即补测。
            if (cfg?.probeOnNetworkChange ?? true) && engineState == .running {
                performProbe()
            }
        } else {
            // 首次上报在线状态等无意义变化，仅更新展示。
            publish()
        }
    }

    // MARK: - 内部：发布

    private func publish() {
        let snap = ConnectivitySnapshot(timestamp: Date(),
                                        engineState: engineState,
                                        pathState: lastPathState,
                                        reachable: reachable,
                                        signalLevel: reachable ? gate.confirmed : .unknown,
                                        smoothedLatencyMs: reachable ? displayedSmoothedMs : nil,
                                        httpStatusCode: lastHttpStatus,
                                        probeErrorKind: lastProbeError,
                                        consecutiveFailures: consecutiveFailures,
                                        pendingLevel: gate.pendingLevel,
                                        pendingStreak: gate.pendingStreak,
                                        isProbing: probeInFlight)
        latest = snap
        let callback = onUpdate
        DispatchQueue.main.async {
            callback?(snap)
        }
    }

    // MARK: - 内部：分析状态

    private func resetAnalysis() {
        samplingWindow.reset()
        gate.reset()
        displayedSmoothedMs = nil
    }

    // MARK: - 内部：定时器

    private func restartTimer(delay: TimeInterval) {
        cancelTimer()
        guard engineState == .running, delay > 0 else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay, repeating: delay)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            guard self.engineState == .running, !self.probeInFlight, self.reachable else { return }
            self.performProbe()
        }
        probeTimer = timer
        timer.resume()
    }

    private func cancelTimer() {
        probeTimer?.cancel()
        probeTimer = nil
    }

    private func teardownInternal() {
        cancelTimer()
        monitor.stop()
        probeInFlight = false
        resetAnalysis()
        consecutiveFailures = 0
        recentSamples.removeAll()
        reachable = true
        lastPathState = .unknown
        lastHttpStatus = nil
        lastProbeError = nil
        backgrounded = false
        config = nil
        configRef = nil
        engineState = .idle
        latest = .makeInitial()
        // 停止时发布一次 idle 快照，通知 UI 清理。
        let snap = latest
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(snap)
        }
    }
}

private extension ConnectivitySnapshot {
    static func makeInitial() -> ConnectivitySnapshot {
        ConnectivitySnapshot(timestamp: Date(),
                             engineState: .idle,
                             pathState: .unknown,
                             reachable: true,
                             signalLevel: .unknown,
                             smoothedLatencyMs: nil,
                             httpStatusCode: nil,
                             probeErrorKind: nil,
                             consecutiveFailures: 0,
                             pendingLevel: nil,
                             pendingStreak: 0,
                             isProbing: false)
    }
}
