Pod::Spec.new do |s|
  s.name             = 'ConnectivityDebugUI'
  s.version          = '0.1.0'
  s.summary          = 'Debug / test page for ConnectivityCore.'
  s.homepage         = 'https://github.com/EggmanQi/ConnectivityKit'
  s.license          = { :type => 'Apache 2.0', :file => 'LICENSE' }
  s.author           = { 'E-Parti' => 'dev@example.invalid' }
  s.source           = { :git => 'https://github.com/EggmanQi/ConnectivityKit.git',
                         :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version         = '5.0'
  s.static_framework      = true

  s.source_files = 'Sources/ConnectivityDebugUI/**/*.swift'
  s.dependency   'ConnectivityCore'
  s.dependency   'ConnectivityUI'
  s.frameworks   = 'UIKit'
end
