import Foundation

/// 档位滞回门：档位切换需连续 N 个采样越过边界，避免图标闪烁。
final class LevelGate {
    private let requiredConsecutive: Int

    /// 当前对外确认的档位
    private(set) var confirmed: SignalLevel = .unknown
    /// 当前累积的目标档位与连续次数（用于调试展示）
    private(set) var pendingLevel: SignalLevel?
    private(set) var pendingStreak: Int = 0

    init(requiredConsecutive: Int) {
        self.requiredConsecutive = max(1, requiredConsecutive)
    }

    /// 喂入一次候选档位，返回最终确认档位。
    /// 候选档位=confirmed 时中断计数；候选变化则重新计数；累计达阈值即切换。
    @discardableResult
    func update(candidate: SignalLevel) -> SignalLevel {
        guard candidate != .unknown else { return confirmed }

        if candidate == confirmed {
            pendingLevel = nil
            pendingStreak = 0
            return confirmed
        }

        if candidate == pendingLevel {
            pendingStreak += 1
        } else {
            pendingLevel = candidate
            pendingStreak = 1
        }

        if pendingStreak >= requiredConsecutive {
            confirmed = candidate
            pendingLevel = nil
            pendingStreak = 0
        }
        return confirmed
    }

    func reset() {
        confirmed = .unknown
        pendingLevel = nil
        pendingStreak = 0
    }
}
