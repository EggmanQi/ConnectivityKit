import UIKit
import ConnectivityCore

/// 房间信号指示组件：状态图片（loading / wifi_0…wifi_4，13×13）+ 右侧延迟文本。
/// 图片只按“数据状态”切换，不随状态变色（色值烘焙在素材里）；
/// 右侧 label 负责颜色/文案：档位 >=3 绿色 #48CD40、档位 <=2 为 50% white。
/// 状态映射：探测中 → loading；离线/1 档 → wifi_0；2…5 档 → wifi_1…wifi_4。
/// 离线时在图标右下角追加红色 ❕ 并显示 "--ms"。
@objc(ConnectivitySignalView)
public final class ConnectivitySignalView: UIView {

    // MARK: 常量

    private static let greenColor = UIColor(red: 0x48 / 255.0,
                                            green: 0xCD / 255.0,
                                            blue: 0x40 / 255.0,
                                            alpha: 1)
    private static let white50 = UIColor(white: 1, alpha: 0.5)

    /// 状态图标的点尺寸（素材按 13×13 @3x 提供）
    private static let iconSize: CGFloat = 13

    // MARK: 子视图

    private let iconImageView = UIImageView()
    private let latencyLabel = UILabel()
    private let badgeLabel = UILabel() // 红色 ❕（离线时显示在图标右下角）

    private var pulseAnimation: CABasicAnimation?

    // MARK: Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: - Public

    /// 以最新探针快照刷新展示。
    @objc public func apply(snapshot: ConnectivityProbeSnapshot) {
        let probing = snapshot.isProbing || (snapshot.isReachable && !snapshot.hasLatency)
        if probing {
            renderLoading()
        } else if !snapshot.isReachable {
            renderOffline()
        } else {
            render(tier: snapshot.displayTier, latencyMs: snapshot.latencyMs)
        }
        invalidateIntrinsicContentSize()
    }

    /// 无探针驱动时隐藏组件（宿主用于进房前/出房后清理）
    @objc public func setVisible(_ visible: Bool) {
        isHidden = !visible
        if !visible { stopPulse() }
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear
        // 纯展示组件，默认不参与点击
        isUserInteractionEnabled = false

        // 状态图片：contentMode 按 13×13 内切，天然与 label centerY 对齐
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.clipsToBounds = false
        addSubview(iconImageView)

        // 延迟文本
        latencyLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        latencyLabel.textColor = Self.white50
        latencyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(latencyLabel)

        // 红色 ❕ 徽标（离线时显示在图标右下角，默认隐藏）
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.text = "❕"
        badgeLabel.textColor = .systemRed
        badgeLabel.font = .systemFont(ofSize: 7, weight: .heavy)
        badgeLabel.textAlignment = .center
        badgeLabel.isHidden = true
        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Self.iconSize),

            latencyLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 4),
            latencyLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            latencyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // 右下角小徽标，稍微探出图标外提示失败，不挤压文本布局
            badgeLabel.trailingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 1),
            badgeLabel.bottomAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: -1),
            badgeLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 12)
        ])
    }

    // MARK: - 渲染

    /// 有延迟的可达状态：tier 2…5 → wifi_1…wifi_4，tier 1（防御）→ wifi_0。
    private func render(tier: Int, latencyMs: Double) {
        stopPulse()
        badgeLabel.isHidden = true

        let clampedTier = min(max(tier, 1), 5)
        // wifi_0…wifi_4 分别对应 1…5 档；图片本身已含档位视觉，无需改色
        iconImageView.image = Self.loadStateImage("wifi_\(clampedTier - 1)")

        let color = clampedTier >= 3 ? Self.greenColor : Self.white50
        latencyLabel.text = "\(Int(latencyMs))ms"
        latencyLabel.textColor = color
    }

    private func renderOffline() {
        stopPulse()
        iconImageView.image = Self.loadStateImage("wifi_0")

        badgeLabel.isHidden = false
        latencyLabel.text = "--ms"
        latencyLabel.textColor = Self.white50
    }

    private func renderLoading() {
        badgeLabel.isHidden = true
        latencyLabel.text = ""
        iconImageView.image = Self.loadStateImage("loading")
        startPulse()
    }

    // MARK: - 资源

    /// 状态图片加载，覆盖三种集成方式的落地位置：
    /// 1) SwiftPM：资源经 `resources: [.process("Resources")]` 打进资源 bundle，用 `Bundle.module` 取；
    /// 2) CocoaPods `s.resources`：平铺进宿主主 bundle，命中 `Bundle.main`；
    /// 3) CocoaPods `s.resource_bundles`：生成 `ConnectivityUI.bundle` 子包，按子包查找。
    /// （素材位于 ConnectivityKit/Sources/ConnectivityUI/Resources）
    private static func loadStateImage(_ name: String) -> UIImage? {
        #if SWIFT_PACKAGE
        if let image = UIImage(named: name, in: .module, compatibleWith: nil) {
            return image
        }
        #endif

        let candidates: [Bundle?] = [
            Bundle.main,
            Bundle(for: ConnectivitySignalView.self)
        ]
        for base in candidates {
            guard let bundle = base else { continue }
            if let image = UIImage(named: name, in: bundle, compatibleWith: nil) {
                return image
            }
        }
        // 子包形式：ConnectivityUI.bundle
        for base in candidates {
            guard let bundle = base,
                  let url = bundle.url(forResource: "ConnectivityUI", withExtension: "bundle"),
                  let image = UIImage(named: name, in: Bundle(url: url), compatibleWith: nil) else { continue }
            return image
        }
        return nil
    }

    // MARK: - Pulse

    private func startPulse() {
        guard pulseAnimation == nil else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.35
        animation.toValue = 1.0
        animation.duration = 0.7
        animation.autoreverses = true
        animation.repeatCount = .infinity
        iconImageView.layer.add(animation, forKey: "signalPulse")
        pulseAnimation = animation
    }

    private func stopPulse() {
        guard pulseAnimation != nil else { return }
        iconImageView.layer.removeAnimation(forKey: "signalPulse")
        iconImageView.alpha = 1
        pulseAnimation = nil
    }

    // MARK: - Intrinsic

    public override var intrinsicContentSize: CGSize {
        let text = latencyLabel.text ?? ""
        let textWidth = text.isEmpty ? 0 : ceil((text as NSString).size(withAttributes: [.font: latencyLabel.font ?? .systemFont(ofSize: 11)]).width)
        let width = Self.iconSize + (text.isEmpty ? 0 : 4 + textWidth)
        return CGSize(width: ceil(width), height: 20)
    }
}
