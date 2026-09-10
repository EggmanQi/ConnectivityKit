import Foundation

/// 供 ObjC 宿主消费的展示快照（均为主线程回调时构造的稳定值）。
/// setter 使用 fileprivate：仅本文件内（监视器）可写，ObjC 侧只读。
@objc(ConnectivityProbeSnapshot)
public final class ConnectivityProbeSnapshot: NSObject {
    /// 是否正在探测（UI 进入 loading 态）
    @objc public fileprivate(set) var isProbing = false
    /// 是否可达（离线为 NO）
    @objc public fileprivate(set) var isReachable = true
    /// 展示档位 1...5（5 档：4 格 → 5 档 ... 0 格 → 1 档）
    @objc public fileprivate(set) var displayTier = 1
    /// 是否有有效平滑延迟
    @objc public fileprivate(set) var hasLatency = false
    /// 平滑延迟毫秒
    @objc public fileprivate(set) var latencyMs: Double = 0
}

/// 探针监视器回调
@objc public protocol ConnectivityProbeMonitorDelegate: AnyObject {
    /// 主线程回调，收到最新展示快照
    func connectivityProbeMonitor(_ monitor: ConnectivityProbeMonitor,
                                  didUpdate snapshot: ConnectivityProbeSnapshot)
}

/// 供 ObjC 宿主使用的高层监视器：封装 ConnectivityEngine，屏蔽 Swift 类型。
/// 生命周期由宿主控制（进房 start / 退房、最小化、被踢 stop）。
@objc(ConnectivityProbeMonitor)
public final class ConnectivityProbeMonitor: NSObject {

    @objc public weak var delegate: ConnectivityProbeMonitorDelegate?

    /// 是否已启动（幂等保护，stop 后可再次 start）
    @objc public private(set) var isRunning = false

    private let engine = ConnectivityEngine()

    public override init() {
        super.init()
    }

    deinit {
        engine.stop()
    }

    /// 以 Base URL 为探针目标启动探测。
    /// - Parameters:
    ///   - baseURL: 当前 API Base URL（根路径探测）
    ///   - interval: 前台轮询间隔（秒），内部下限 5s
    @objc public func start(baseURL: URL, interval: TimeInterval) {
        guard !isRunning else { return }
        isRunning = true

        engine.historyStore = nil
        engine.onUpdate = { [weak self] snap in
            guard let self = self else { return }
            self.publish(snap)
        }

        var cfg = ConnectivityConfig(target: ProbeTarget(url: baseURL))
        cfg.probeInterval = max(5, interval)
        engine.start(config: cfg)
    }

    @objc public func stop() {
        guard isRunning else { return }
        isRunning = false
        engine.onUpdate = nil
        engine.stop()
    }

    /// 手动立即探测一次
    @objc public func refreshNow() {
        engine.refreshNow()
    }

    /// 将引擎快照映射为展示快照。
    /// 与监视器内部回调语义完全一致，供 Swift 侧（Debug 页 / UI 复用）直接构造出可喂给
    /// `ConnectivitySignalView` 的快照。
    public static func makeSnapshot(from snap: ConnectivitySnapshot) -> ConnectivityProbeSnapshot {
        let out = ConnectivityProbeSnapshot()
        out.isProbing = snap.isProbing
        // “无法连接”：网络路径离线，或最近一次探测未拿到服务器响应（路径在线但服务器不可达）。
        // 注意：4xx/5xx 也视为“可达”（有响应即有延迟），仅网络层失败归类为不可连。
        let serverDown = !snap.reachable || (snap.probeErrorKind != nil && snap.httpStatusCode == nil)
        out.isReachable = !serverDown
        out.hasLatency = !serverDown && snap.smoothedLatencyMs != nil
        out.latencyMs = out.hasLatency ? (snap.smoothedLatencyMs ?? 0) : 0
        out.displayTier = out.hasLatency ? tier(for: effectiveLevel(of: snap)) : 1
        return out
    }

    /// App 进入后台：暂停探测（省电），回前台自动恢复并补测。
    @objc public func handleAppDidEnterBackground() {
        guard isRunning else { return }
        engine.handleAppDidEnterBackground()
    }

    @objc public func handleAppDidBecomeActive() {
        guard isRunning else { return }
        engine.handleAppDidBecomeActive()
    }

    // MARK: - Private

    private func publish(_ snap: ConnectivitySnapshot) {
        delegate?.connectivityProbeMonitor(self, didUpdate: Self.makeSnapshot(from: snap))
    }

    /// 已确认档位优先；初次无确认结果时先用候选档位（门限刚起步）
    private static func effectiveLevel(of snap: ConnectivitySnapshot) -> SignalLevel {
        guard snap.reachable else { return .unknown }
        if snap.signalLevel != .unknown { return snap.signalLevel }
        if let pending = snap.pendingLevel { return pending }
        return .unknown
    }

    private static func tier(for level: SignalLevel) -> Int {
        switch level {
        case .excellent: return 5
        case .good: return 4
        case .fair: return 3
        case .poor: return 2
        case .unknown: return 1
        }
    }
}
