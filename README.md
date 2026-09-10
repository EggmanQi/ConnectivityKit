# ConnectivityKit

网络状态组件-ping base url

网络质量探测 / 心跳监控组件（iOS），包含可复用的探测内核、房间内信号指示 UI，以及一个调试测试页。

## 组成

| Target / Pod | 说明 | 依赖 |
|---|---|---|
| `ConnectivityCore` | 纯逻辑探测内核（无 UIKit）：轮询、前后台、网络切换、平滑与档位滞回、历史存储、ObjC 桥接层 | Foundation / Network |
| `ConnectivityUI` | 房间内信号指示组件 `ConnectivitySignalView`（状态图片 + 延迟文本） | ConnectivityCore / UIKit |
| `ConnectivityDebugUI` | 调试测试页 `ConnectivityDebugViewController`（实时快照、历史分页、间隔调节、真实组件预览） | ConnectivityCore / ConnectivityUI |

- 平台：iOS 13.0+
- Swift：5.0（包清单 `swift-tools-version:5.3`，需 Xcode 12+）

## 目录结构

```
ConnectivityKit/
├── Package.swift
├── ConnectivityCore.podspec
├── ConnectivityUI.podspec
├── ConnectivityDebugUI.podspec
├── LICENSE
└── Sources/
    ├── ConnectivityCore/
    ├── ConnectivityUI/
    │   ├── ConnectivitySignalView.swift
    │   └── Resources/            # loading.png / wifi_0…wifi_4.png（13×13 pt，@3x 39px）
    └── ConnectivityDebugUI/
```

## 接入方式

### CocoaPods（本地联调）

```ruby
pod 'ConnectivityCore',     :path => 'ConnectivityKit'
pod 'ConnectivityUI',       :path => 'ConnectivityKit'
pod 'ConnectivityDebugUI',  :path => 'ConnectivityKit', :configurations => ['Debug']
```

### CocoaPods（远程私有源）

```ruby
pod 'ConnectivityCore'
pod 'ConnectivityUI'
pod 'ConnectivityDebugUI', :configurations => ['Debug']
```

三个 podspec 的 `s.source` 已指向本仓库并取 `s.version` 作为 tag，使用前需先推送对应 tag（见“发布”）。

### Swift Package Manager

```swift
.package(url: "https://git.moliparty.com/xindegitzhanghao/ConnectivityKit.git", from: "0.1.0")
```

按需引入 `ConnectivityCore` / `ConnectivityUI` / `ConnectivityDebugUI`。

资源通过 `resources: [.process("Resources")]` 打进资源 bundle，组件内部用 `Bundle.module` 读取；CocoaPods 侧用 `resource_bundles` 生成 `ConnectivityUI.bundle`。三种落地方式（SPM / `s.resources` / `s.resource_bundles`）均已兼容，无需调用方额外配置。

## 使用

### Swift

```swift
let monitor = ConnectivityProbeMonitor()
monitor.start(baseURL: URL(string: "https://api.example.com")!, interval: 10)

// 展示组件
let signal = ConnectivitySignalView()
signal.setVisible(true)
signal.apply(snapshot: ConnectivityProbeMonitor.makeSnapshot(from: engine.currentSnapshot()))
```

`ConnectivityProbeMonitor` 提供 delegate 回调：

```swift
func connectivityProbeMonitor(_ monitor: ConnectivityProbeMonitor,
                              didUpdate snapshot: ConnectivityProbeSnapshot)
```

### Objective-C

```objc
#import <ConnectivityCore/ConnectivityCore-Swift.h>
#import <ConnectivityUI/ConnectivityUI-Swift.h>

ConnectivityProbeMonitor *monitor = [ConnectivityProbeMonitor new];
monitor.delegate = self;
[monitor startWithBaseURL:baseURL interval:10];

[signalView applyWithSnapshot:snapshot];
[signalView setVisible:YES];
```

生命周期：进房 `start`，退房 / 最小化 / 被踢 `stop`；`handleAppDidEnterBackground` / `handleAppDidBecomeActive` 由宿主前后台通知桥接。

### 档位与展示映射

| 档位 | SignalLevel | 图标 |
|---|---|---|
| 1 | unknown / 不可达 | `wifi_0`（不可达时叠加红色 ❕，文本 `--ms`） |
| 2 | poor | `wifi_1` |
| 3 | fair | `wifi_2` |
| 4 | good | `wifi_3` |
| 5 | excellent | `wifi_4` |

探测中显示 `loading`（脉冲动画）。图标按状态切图、颜色烘焙在素材中；右侧延迟文本档位 ≥3 为 `#48CD40`，≤2 为 50% 白。

## 发布

```bash
git tag 0.1.0 && git push origin 0.1.0

pod repo push <私有源名> ConnectivityCore.podspec
pod repo push <私有源名> ConnectivityUI.podspec
pod repo push <私有源名> ConnectivityDebugUI.podspec
```

三个 pod 共用同一个 tag（`s.version`），版本号需同步递增。

## 注意

- 许可证：Apache License 2.0，详见 [LICENSE](LICENSE)。
- `ConnectivityDebugUI` 仅供 Debug 使用，请以 `:configurations => ['Debug']` 接入生产工程。
- podspec 中 `s.author` 的联系邮箱仍为占位值，正式发布前请替换。
