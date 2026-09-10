Pod::Spec.new do |s|
  s.name             = 'ConnectivityCore'
  s.version          = '0.1.0'
  s.summary          = 'Reusable network quality probe / heartbeat monitor core (no UIKit).'
  s.homepage         = 'https://git.moliparty.com/xindegitzhanghao/ConnectivityKit'
  s.license          = { :type => 'Apache 2.0', :file => 'LICENSE' }
  s.author           = { 'E-Parti' => 'dev@example.invalid' }
  s.source           = { :git => 'https://git.moliparty.com/xindegitzhanghao/ConnectivityKit.git',
                         :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version         = '5.0'
  s.static_framework      = true

  s.source_files = 'Sources/ConnectivityCore/**/*.swift'
  s.frameworks   = 'Foundation', 'Network'
end
