import Foundation

/// 网络质量档位（由平滑后的延迟决定）。
/// unknown 表示尚未有足够样本或处于离线态。
public enum SignalLevel: Int, Comparable, Codable, CaseIterable {
    case unknown = 0
    case poor = 1
    case fair = 2
    case good = 3
    case excellent = 4

    public static func < (lhs: SignalLevel, rhs: SignalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
