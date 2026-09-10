import UIKit
import ConnectivityCore
import ConnectivityUI

/// 调试 / 测试页面：实时展示引擎快照与历史记录，支持启停、手动探测、轮询间隔调节。
/// 页面生命周期即引擎生命周期：打开即启动（idle 时），pop 后停止并清理。
public final class ConnectivityDebugViewController: UIViewController {

    /// 只读暴露引擎，宿主（Debug）可在页面打开前替换历史存储等。
    public private(set) lazy var engine: ConnectivityEngine = {
        let engine = ConnectivityEngine()
        engine.historyStore = InMemoryHistoryStore()
        return engine
    }()

    private var config: ConnectivityConfig

    // MARK: UI

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private let statusIconHost = UIView()
    private let statusBars = SignalBarsView()
    private let statusTitleLabel = UILabel()
    private let statusDetailLabel = UILabel()
    private let latencyLabel = UILabel()

    // MARK: 真实组件预览（与房间同款 ConnectivitySignalView）

    /// 仿房间深色胶囊宿主，让素材内置的浅色图标可读
    private let previewHost = UIView()
    /// 真实房间信号组件
    private let realSignalView = ConnectivitySignalView()

    private var startButton: UIButton!
    private var stopButton: UIButton!
    private var probeButton: UIButton!
    private var clearButton: UIButton!

    private var minusButton: UIButton!
    private var plusButton: UIButton!
    private var intervalValueLabel: UILabel!

    // MARK: 历史分页

    private let pageSize = 20
    private var historyPage = 0
    private var historyAll: [ConnectivityHistoryEntry] = []

    private var historyHeaderCache: UIView?
    private var historyPageLabel: UILabel?
    private var historyPrevButton: UIButton?
    private var historyNextButton: UIButton?

    private static let intervalMin: TimeInterval = 5
    private static let intervalStep: TimeInterval = 5

    public init(config: ConnectivityConfig) {
        self.config = config
        super.init(nibName: nil, bundle: nil)
        title = "API 状态"
    }

    /// ObjC 宿主便捷入口：基于 Base URL 根路径的默认探测配置。
    @objc public convenience init(baseURL: URL) {
        self.init(config: ConnectivityConfig(target: ProbeTarget(url: baseURL)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        engine.stop()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureTableView()
        configureHeader()
        observeAppLifecycle()

        engine.onUpdate = { [weak self] _ in
            self?.refreshUI()
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if engine.engineState == .idle {
            engine.start(config: config)
        }
        refreshUI()
    }

    // MARK: - 生命周期桥

    private func observeAppLifecycle() {
        let center = NotificationCenter.default
        center.addObserver(self,
                           selector: #selector(appDidEnterBackground),
                           name: UIApplication.didEnterBackgroundNotification,
                           object: nil)
        center.addObserver(self,
                           selector: #selector(appWillEnterForeground),
                           name: UIApplication.willEnterForegroundNotification,
                           object: nil)
    }

    @objc private func appDidEnterBackground() {
        engine.handleAppDidEnterBackground()
    }

    @objc private func appWillEnterForeground() {
        engine.handleAppDidBecomeActive()
    }

    // MARK: - TableView 搭建

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - 顶部卡片

    private func configureHeader() {
        let header = UIView()
        header.frame = CGRect(x: 0, y: 0, width: 320, height: 296)
        header.autoresizingMask = .flexibleWidth

        let statusCard = makeCard()
        statusCard.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(statusCard)
        configureStatusContent(in: statusCard)

        let componentCard = makeCard()
        componentCard.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(componentCard)
        configureComponentContent(in: componentCard)

        let iconRow = makeIconActionRow()
        iconRow.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(iconRow)

        let intervalCard = makeCard()
        intervalCard.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(intervalCard)
        configureIntervalContent(in: intervalCard)

        NSLayoutConstraint.activate([
            statusCard.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            statusCard.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            statusCard.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            statusCard.heightAnchor.constraint(equalToConstant: 92),

            componentCard.topAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: 12),
            componentCard.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            componentCard.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            componentCard.heightAnchor.constraint(equalToConstant: 44),

            iconRow.topAnchor.constraint(equalTo: componentCard.bottomAnchor, constant: 12),
            iconRow.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            iconRow.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            iconRow.heightAnchor.constraint(equalToConstant: 58),

            intervalCard.topAnchor.constraint(equalTo: iconRow.bottomAnchor, constant: 12),
            intervalCard.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            intervalCard.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            intervalCard.heightAnchor.constraint(equalToConstant: 76)
        ])

        header.frame.size.height = 12 + 92 + 12 + 44 + 12 + 58 + 12 + 76 + 12
        tableView.tableHeaderView = header
    }

    private func makeCard() -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 14
        card.layer.masksToBounds = true
        return card
    }

    private func configureStatusContent(in card: UIView) {
        statusIconHost.translatesAutoresizingMaskIntoConstraints = false
        statusIconHost.layer.cornerRadius = 28
        statusBars.translatesAutoresizingMaskIntoConstraints = false
        statusIconHost.addSubview(statusBars)
        card.addSubview(statusIconHost)

        statusTitleLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        statusTitleLabel.text = "检测中…"
        statusTitleLabel.adjustsFontSizeToFitWidth = true

        statusDetailLabel.font = .systemFont(ofSize: 12)
        statusDetailLabel.textColor = .secondaryLabel
        statusDetailLabel.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [statusTitleLabel, statusDetailLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(textStack)

        latencyLabel.font = .monospacedDigitSystemFont(ofSize: 26, weight: .bold)
        latencyLabel.textAlignment = .right
        latencyLabel.adjustsFontSizeToFitWidth = true
        latencyLabel.setContentHuggingPriority(.required, for: .horizontal)
        latencyLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        latencyLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(latencyLabel)

        NSLayoutConstraint.activate([
            statusIconHost.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            statusIconHost.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            statusIconHost.widthAnchor.constraint(equalToConstant: 56),
            statusIconHost.heightAnchor.constraint(equalToConstant: 56),

            statusBars.centerXAnchor.constraint(equalTo: statusIconHost.centerXAnchor),
            statusBars.centerYAnchor.constraint(equalTo: statusIconHost.centerYAnchor),
            statusBars.widthAnchor.constraint(equalToConstant: 30),
            statusBars.heightAnchor.constraint(equalToConstant: 30),

            textStack.leadingAnchor.constraint(equalTo: statusIconHost.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: latencyLabel.leadingAnchor, constant: -8),

            latencyLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            latencyLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            latencyLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 76)
        ])
    }

    /// 状态卡下方新增“真实组件预览区”：深色胶囊里放与房间同款的 ConnectivitySignalView。
    /// 图片只展示数据状态（loading / wifi_0…wifi_4），右侧 label 按档位着色，胶囊宽度随文案自适应。
    private func configureComponentContent(in card: UIView) {
        let caption = UILabel()
        caption.text = "房间信号组件（真实）"
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = .secondaryLabel
        caption.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(caption)

        previewHost.backgroundColor = UIColor(white: 0.13, alpha: 1)
        previewHost.layer.cornerRadius = 13
        previewHost.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(previewHost)

        realSignalView.translatesAutoresizingMaskIntoConstraints = false
        realSignalView.setVisible(false) // 未启动前先隐藏
        previewHost.addSubview(realSignalView)

        NSLayoutConstraint.activate([
            caption.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            caption.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            caption.trailingAnchor.constraint(lessThanOrEqualTo: previewHost.leadingAnchor, constant: -10),

            previewHost.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            previewHost.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            previewHost.heightAnchor.constraint(equalToConstant: 26),
            // 胶囊宽度跟随组件文案自适应（组件 intrinsicContentSize 随延迟文本变化）
            previewHost.widthAnchor.constraint(equalTo: realSignalView.widthAnchor, constant: 20),

            realSignalView.centerXAnchor.constraint(equalTo: previewHost.centerXAnchor),
            realSignalView.centerYAnchor.constraint(equalTo: previewHost.centerYAnchor)
        ])
    }

    private func configureIntervalContent(in card: UIView) {
        let caption = UILabel()
        caption.text = "轮询间隔"
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabel

        intervalValueLabel = UILabel()
        intervalValueLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        intervalValueLabel.textAlignment = .center

        let textStack = UIStackView(arrangedSubviews: [caption, intervalValueLabel])
        textStack.axis = .vertical
        textStack.spacing = 0
        textStack.alignment = .center
        textStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(textStack)

        minusButton = makeCircleIconButton(symbol: "minus", action: #selector(didTapMinus))
        plusButton = makeCircleIconButton(symbol: "plus", action: #selector(didTapPlus))
        let controls = UIStackView(arrangedSubviews: [minusButton, textStack, plusButton])
        controls.axis = .horizontal
        controls.spacing = 16
        controls.alignment = .center
        controls.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(controls)

        NSLayoutConstraint.activate([
            controls.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            controls.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            minusButton.widthAnchor.constraint(equalToConstant: 40),
            minusButton.heightAnchor.constraint(equalToConstant: 40),
            plusButton.widthAnchor.constraint(equalToConstant: 40),
            plusButton.heightAnchor.constraint(equalToConstant: 40),
            controls.widthAnchor.constraint(lessThanOrEqualTo: card.widthAnchor, constant: -20)
        ])
    }

    private func makeIconActionRow() -> UIStackView {
        startButton = makeIconButton(symbol: "play.fill", title: "启动", action: #selector(didTapStart))
        stopButton = makeIconButton(symbol: "stop.fill", title: "停止", action: #selector(didTapStop))
        probeButton = makeIconButton(symbol: "bolt.fill", title: "立即检测", action: #selector(didTapProbe))
        clearButton = makeIconButton(symbol: "trash", title: "清空历史", action: #selector(didTapClear))

        let row = UIStackView(arrangedSubviews: [startButton, stopButton, probeButton, clearButton])
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8
        return row
    }

    private func makeIconButton(symbol: String, title: String, action: Selector) -> UIButton {
        let image = UIImage(systemName: symbol)
        let button = UIButton(type: .system)
        button.setImage(image, for: .normal)
        button.tintColor = .systemBlue
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 10)
        button.titleLabel?.textAlignment = .center
        button.alignImageAndTitleVertically(spacing: 2)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makeCircleIconButton(symbol: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        let image = UIImage(systemName: symbol)
        button.setImage(image, for: .normal)
        button.tintColor = .systemBlue
        button.backgroundColor = .systemGray6
        button.layer.cornerRadius = 20
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    // MARK: - 动作

    @objc private func didTapStart() {
        engine.start(config: config)
        refreshUI()
    }

    @objc private func didTapStop() {
        engine.stop()
        refreshUI()
    }

    @objc private func didTapProbe() {
        engine.refreshNow()
    }

    @objc private func didTapClear() {
        engine.historyStore?.clear()
        historyPage = 0
        reloadHistory()
        refreshUI()
    }

    @objc private func didTapMinus() {
        adjustInterval(by: -Self.intervalStep)
    }

    @objc private func didTapPlus() {
        adjustInterval(by: Self.intervalStep)
    }

    private func adjustInterval(by delta: TimeInterval) {
        let next = max(Self.intervalMin, config.probeInterval + delta)
        guard next != config.probeInterval else { return }
        config.probeInterval = next
        engine.setProbeInterval(next)
        refreshUI()
    }

    // MARK: - 刷新

    private func refreshUI() {
        let snap = engine.currentSnapshot()
        updateStatusCard(snap)
        updateComponentPreview(snap)
        updateButtons(snap)
        updateIntervalRow()
        reloadHistory()
        tableView.reloadData()
    }

    /// 用引擎当前快照驱动真实组件预览。
    /// 引擎停止（idle）时隐藏组件（与房间“不监控则不显示”一致），否则走真实组件的渲染路径。
    private func updateComponentPreview(_ snap: ConnectivitySnapshot) {
        guard engine.engineState != .idle else {
            realSignalView.setVisible(false)
            return
        }
        realSignalView.setVisible(true)
        realSignalView.apply(snapshot: ConnectivityProbeMonitor.makeSnapshot(from: snap))
    }

    private func updateStatusCard(_ snap: ConnectivitySnapshot) {
        let accent: UIColor
        let iconFill: Int
        var title = ""
        var detailParts: [String] = []

        switch (snap.engineState, snap.reachable) {
        case (.idle, _):
            accent = .systemGray
            iconFill = 0
            title = "已停止"
        case (_, false):
            accent = .systemRed
            iconFill = 0
            title = "离线"
            detailParts.append(snap.pathState.displayName)
        case (.running, true):
            switch snap.signalLevel {
            case .unknown:
                accent = .systemGray
                iconFill = 0
                title = "检测中…"
            case let level:
                accent = level.displayColor
                iconFill = level.rawValue
                title = level.displayName
            }
        case (.paused, _):
            accent = .systemOrange
            iconFill = snap.signalLevel == .unknown ? 0 : snap.signalLevel.rawValue
            title = "后台挂起"
        }

        statusBars.activeCount = iconFill
        statusBars.tintColor = accent
        statusBars.setNeedsDisplay()
        statusIconHost.backgroundColor = accent.withAlphaComponent(0.14)
        statusTitleLabel.text = title
        statusTitleLabel.textColor = accent

        detailParts.append("\(snap.pathState.displayName) · \(snap.engineState.displayName)")
        if let status = snap.httpStatusCode {
            detailParts.append("HTTP \(status)")
        } else if let error = snap.probeErrorKind, snap.reachable {
            detailParts.append("探针错误 \(error.rawValue)")
        }
        detailParts.append("失败 \(snap.consecutiveFailures)")
        statusDetailLabel.text = detailParts.joined(separator: "  ")

        if snap.reachable, snap.engineState != .idle {
            if let ms = snap.smoothedLatencyMs {
                latencyLabel.text = String(format: "%.0f ms", ms)
                latencyLabel.textColor = accent
            } else {
                latencyLabel.text = "—"
                latencyLabel.textColor = .secondaryLabel
            }
        } else {
            latencyLabel.text = "—"
            latencyLabel.textColor = .secondaryLabel
        }
    }

    private func updateButtons(_ snap: ConnectivitySnapshot) {
        startButton.isEnabled = (snap.engineState == .idle)
        stopButton.isEnabled = (snap.engineState == .running || snap.engineState == .paused)
        probeButton.isEnabled = (snap.engineState == .running)
        let disabledColor = UIColor.systemBlue.withAlphaComponent(0.35)
        startButton.tintColor = startButton.isEnabled ? .systemBlue : disabledColor
        stopButton.tintColor = stopButton.isEnabled ? .systemBlue : disabledColor
        probeButton.tintColor = probeButton.isEnabled ? .systemBlue : disabledColor
    }

    private func updateIntervalRow() {
        intervalValueLabel.text = "\(Int(config.probeInterval)) s"
        minusButton.isEnabled = config.probeInterval > Self.intervalMin
        minusButton.tintColor = minusButton.isEnabled ? .systemBlue : .systemGray
    }

    private func reloadHistory() {
        historyAll = (engine.historyStore?.entries(limit: 10000) ?? []).reversed()
        let totalPages = max(1, Int(ceil(Double(historyAll.count) / Double(pageSize))))
        if historyPage >= totalPages {
            historyPage = totalPages - 1
        }
    }

    private var historyPageRows: [ConnectivityHistoryEntry] {
        let start = historyPage * pageSize
        guard start < historyAll.count else { return [] }
        return Array(historyAll[start..<min(start + pageSize, historyAll.count)])
    }

    // MARK: 历史分页 Header

    private func historyHeader() -> UIView {
        if let cached = historyHeaderCache {
            return cached
        }
        let header = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 30))

        let title = UILabel()
        title.text = "历史（成功采样）"
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .secondaryLabel
        title.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)

        func chevron(_ symbol: String, action: Selector) -> UIButton {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: symbol), for: .normal)
            button.tintColor = .systemBlue
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: action, for: .touchUpInside)
            return button
        }

        let prev = chevron("chevron.left", action: #selector(didTapHistoryPrev))
        let pageLabel = UILabel()
        pageLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        pageLabel.textColor = .secondaryLabel
        pageLabel.textAlignment = .center
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        let next = chevron("chevron.right", action: #selector(didTapHistoryNext))

        header.addSubview(prev)
        header.addSubview(pageLabel)
        header.addSubview(next)

        historyPageLabel = pageLabel
        historyPrevButton = prev
        historyNextButton = next

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 0),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            next.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: 0),
            next.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            next.widthAnchor.constraint(equalToConstant: 30),
            next.heightAnchor.constraint(equalToConstant: 30),

            pageLabel.trailingAnchor.constraint(equalTo: next.leadingAnchor, constant: -4),
            pageLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            prev.trailingAnchor.constraint(equalTo: pageLabel.leadingAnchor, constant: -4),
            prev.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            prev.widthAnchor.constraint(equalToConstant: 30),
            prev.heightAnchor.constraint(equalToConstant: 30)
        ])

        historyHeaderCache = header
        return header
    }

    private func updateHistoryHeaderControls() {
        let totalPages = max(1, Int(ceil(Double(historyAll.count) / Double(pageSize))))
        historyPageLabel?.text = "\(historyPage + 1)/\(totalPages)"
        historyPrevButton?.isEnabled = historyPage > 0
        historyNextButton?.isEnabled = historyPage < totalPages - 1
        historyPrevButton?.tintColor = (historyPage > 0) ? .systemBlue : .systemGray
        historyNextButton?.tintColor = (historyPage < totalPages - 1) ? .systemBlue : .systemGray
    }

    @objc private func didTapHistoryPrev() {
        guard historyPage > 0 else { return }
        historyPage -= 1
        updateHistoryHeaderControls()
        tableView.reloadData()
    }

    @objc private func didTapHistoryNext() {
        let totalPages = max(1, Int(ceil(Double(historyAll.count) / Double(pageSize))))
        guard historyPage < totalPages - 1 else { return }
        historyPage += 1
        updateHistoryHeaderControls()
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource / Delegate

extension ConnectivityDebugViewController: UITableViewDataSource, UITableViewDelegate {

    private enum Section: Int, CaseIterable {
        case state
        case config
        case history

        var title: String {
            switch self {
            case .state: return "实时状态"
            case .config: return "配置"
            case .history: return ""
            }
        }
    }

    public func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let s = Section(rawValue: section)
        return (s == .history) ? nil : s?.title
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard Section(rawValue: section) == .history else { return nil }
        updateHistoryHeaderControls()
        return historyHeader()
    }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        Section(rawValue: section) == .history ? 34 : 40
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .state: return 7
        case .config: return 4
        case .history: return historyPageRows.count
        default: return 0
        }
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.selectionStyle = .none
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = .systemFont(ofSize: 13)
        cell.textLabel?.textColor = .label

        let snap = engine.currentSnapshot()
        switch Section(rawValue: indexPath.section) {
        case .state:
            cell.accessoryType = .none
            cell.textLabel?.text = stateRow(at: indexPath.row, snap: snap)
        case .config:
            cell.accessoryType = .none
            cell.textLabel?.text = configRow(at: indexPath.row)
        case .history:
            let rows = historyPageRows
            guard rows.indices.contains(indexPath.row) else { break }
            cell.textLabel?.text = Self.describe(entry: rows[indexPath.row])
        default:
            break
        }
        return cell
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }

    public func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        40
    }

    // MARK: 行内容

    private func stateRow(at index: Int, snap: ConnectivitySnapshot) -> String {
        switch index {
        case 0: return "引擎状态：\(snap.engineState.displayName)"
        case 1: return "网络路径：\(snap.pathState.displayName)"
        case 2: return "可达：\(snap.reachable ? "是" : "否")"
        case 3: return "信号档位：\(snap.signalLevel.displayName)（待确认 \(snap.pendingLevel?.displayName ?? "-") ×\(snap.pendingStreak)/\(config.hysteresisRequiredConsecutive)）"
        case 4: return "平滑延迟：\(snap.smoothedLatencyMs.map { String(format: "%.0f ms", $0) } ?? "-")"
        case 5: return "最近 HTTP：\(snap.httpStatusCode.map(String.init) ?? "-")"
        case 6: return "连续失败：\(snap.consecutiveFailures) · 探针错误：\(snap.probeErrorKind?.rawValue ?? "-")"
        default: return ""
        }
    }

    private func configRow(at index: Int) -> String {
        let cfg = config
        let extras = cfg.additionalTargets.map { $0.url.absoluteString }.joined(separator: "、")
        switch index {
        case 0: return "探针：\(cfg.target.method) \(cfg.target.url.absoluteString)"
        case 1: return "附加目标：\(extras.isEmpty ? "-" : extras)"
        case 2: return "间隔：\(Int(cfg.probeInterval))s · 超时：\(Int(cfg.target.timeout))s · 后台阈值：\(Int(cfg.backgroundPauseThreshold))s"
        case 3: return "权重：\(cfg.sampling.weights.map { String($0) }.joined(separator: "/")) · 档位阈值：excellent\(Int(cfg.qualityBands.excellentMaxMs)) good\(Int(cfg.qualityBands.goodMaxMs)) fair\(Int(cfg.qualityBands.fairMaxMs)) · 滞回≥\(cfg.hysteresisRequiredConsecutive)次"
        default: return ""
        }
    }

    private static func describe(entry: ConnectivityHistoryEntry) -> String {
        let time = Self.timeFormatter.string(from: entry.timestamp)
        let latency = entry.smoothedLatencyMs.map { String(format: "%.0f ms", $0) } ?? "-"
        let level = SignalLevel(rawValue: entry.signalLevelRaw)?.displayName ?? "-"
        let status = entry.httpStatusCode.map(String.init) ?? "-"
        let error = entry.errorKind ?? ""
        return "\(time)  [\(level)]  \(latency)  HTTP \(status)  \(error)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - 信号柱视图（自由发挥的顶部指示器）

/// 四格信号柱。activeCount = 0..4，0 时整体变暗表示无信号/离线。
final class SignalBarsView: UIView {
    var activeCount = 0 {
        didSet { setNeedsDisplay() }
    }

    private let barFractions: [CGFloat] = [0.4, 0.6, 0.8, 1.0]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let barCount = barFractions.count
        let spacing: CGFloat = 3
        let barWidth = max(2, (rect.width - CGFloat(barCount - 1) * spacing) / CGFloat(barCount))
        let fullHeight = rect.height

        let enabledColor = tintColor ?? .systemBlue
        let disabledColor = UIColor.secondaryLabel.withAlphaComponent(0.28)

        for i in 0..<barCount {
            let barHeight = fullHeight * barFractions[i]
            let x = rect.minX + CGFloat(i) * (barWidth + spacing)
            let y = rect.maxY - barHeight
            let barRect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = UIBezierPath(roundedRect: barRect, cornerRadius: barWidth * 0.4)
            (i < activeCount ? enabledColor : disabledColor).setFill()
            path.fill()
        }
        _ = context
    }
}

// MARK: - UIButton 图标+文字 纵向排布

extension UIButton {
    fileprivate func alignImageAndTitleVertically(spacing: CGFloat) {
        let imageSize = imageView?.intrinsicContentSize ?? .zero
        let titleSize = titleLabel?.intrinsicContentSize ?? .zero
        guard imageSize != .zero else { return }

        contentEdgeInsets = UIEdgeInsets(top: (imageSize.height + spacing) / 2,
                                         left: 0,
                                         bottom: (titleSize.height + spacing) / 2,
                                         right: 0)
        imageEdgeInsets = UIEdgeInsets(top: -(titleSize.height + spacing) / 2,
                                       left: 0,
                                       bottom: (titleSize.height + spacing) / 2,
                                       right: -imageSize.width)
        titleEdgeInsets = UIEdgeInsets(top: (imageSize.height + spacing) / 2,
                                       left: -imageSize.width,
                                       bottom: -(imageSize.height + spacing) / 2,
                                       right: 0)
    }
}

// MARK: - 展示扩展

extension ConnectivityEngineState {
    var displayName: String {
        switch self {
        case .idle: return "idle（停止）"
        case .running: return "running（运行）"
        case .paused: return "paused（后台）"
        }
    }
}

extension NetworkPathState {
    var displayName: String {
        switch self {
        case .unknown: return "unknown"
        case .offline: return "离线"
        case .wifi: return "Wi-Fi"
        case .cellular: return "蜂窝"
        }
    }
}

extension SignalLevel {
    var displayName: String {
        switch self {
        case .unknown: return "未定"
        case .poor: return "差"
        case .fair: return "一般"
        case .good: return "良好"
        case .excellent: return "优秀"
        }
    }

    var displayColor: UIColor {
        switch self {
        case .unknown: return .systemGray
        case .poor: return .systemRed
        case .fair: return .systemOrange
        case .good: return .systemGreen
        case .excellent: return .systemGreen
        }
    }
}
