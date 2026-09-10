import Foundation
import Network

/// 网络可达状态
public enum NetworkPathState: Equatable {
    case unknown
    case offline
    case wifi
    case cellular
}

/// NWPathMonitor 封装，自包含，不依赖宿主的 AF/YYReachability。
/// 回调在私有串行队列上执行，调用方按需自行切主线程。
public final class ConnectivityNetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "connectivitykit.network.monitor")

    public var onStatusChange: ((NetworkPathState) -> Void)?

    /// 最近一次状态；初始为 unknown，调用 start() 后尽快给出真实状态。
    public private(set) var currentState: NetworkPathState = .unknown

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let state = Self.map(path)
            self.currentState = state
            self.onStatusChange?(state)
        }
    }

    public func start() {
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }

    private static func map(_ path: NWPath) -> NetworkPathState {
        guard path.status == .satisfied else { return .offline }
        if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
            return .wifi
        }
        if path.usesInterfaceType(.cellular) {
            return .cellular
        }
        return .offline
    }
}
