Pod::Spec.new do |s|
  s.name         = 'Internal_CDZQRScanningViewController'
  s.version      = '1.0.10'
  s.summary      = 'Easy QR code scanning on iOS 7.'
  s.homepage     = 'https://github.com/cdzombak/CDZQRScanningViewController'
  s.license      = 'MIT'
  s.author       = { 'Chris Dzombak' => 'chris@chrisdzombak.net' }

  s.source       = { :git => 'https://github.com/tasboa/CDZQRScanningViewController.git', :tag => "#{s.version}" }
  s.platform     = :ios, '7.0'

  s.source_files = 'Source/*.{h,m}'
  s.public_header_files = 'Source/*.h'
  s.frameworks   = ['AVFoundation', 'UIKit']
  s.requires_arc = true
end
