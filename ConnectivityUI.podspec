Pod::Spec.new do |s|
  s.name             = 'ConnectivityUI'
  s.version          = '0.1.0'
  s.summary          = 'In-room signal indicator UI built on ConnectivityCore.'
  s.homepage         = 'https://github.com/EggmanQi/ConnectivityKit'
  s.license          = { :type => 'Apache 2.0', :file => 'LICENSE' }
  s.author           = { 'E-Parti' => 'dev@example.invalid' }
  s.source           = { :git => 'https://github.com/EggmanQi/ConnectivityKit.git',
                         :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version         = '5.0'
  s.static_framework      = true

  s.source_files     = 'Sources/ConnectivityUI/**/*.swift'
  # 打进独立的 ConnectivityUI.bundle，避免 loading.png / wifi_*.png 这类通用名
  # 平铺进宿主主 bundle 后与其它 pod 冲突
  s.resource_bundles = { 'ConnectivityUI' => ['Sources/ConnectivityUI/Resources/*.png'] }
  s.dependency       'ConnectivityCore'
  s.frameworks       = 'UIKit'
end
