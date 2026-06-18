Pod::Spec.new do |s|
  s.name             = 'ApplaudIQEmbed'
  s.version          = '1.0.0'
  s.summary          = 'Embed the Applaud IQ recognition portal in a native iOS app.'
  s.description      = <<-DESC
    ApplaudIQEmbed renders the Applaud IQ recognition portal in a WKWebView with auto
    or manual login. Pass your publishable key (and a one-time token for auto-login),
    present the view controller, and handle the lifecycle callbacks.
  DESC
  s.homepage         = 'https://github.com/therewardstore/applaudiq-embed-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Arulraj V' => 'abofficial1997@gmail.com' }
  s.source           = { :git => 'https://github.com/therewardstore/applaudiq-embed-ios.git', :tag => s.version.to_s }

  s.ios.deployment_target = '14.0'
  s.swift_versions   = ['5.9']
  s.source_files     = 'Sources/ApplaudIQEmbed/**/*.swift'
  s.frameworks       = 'WebKit', 'AuthenticationServices', 'UIKit'
end
