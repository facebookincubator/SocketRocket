Pod::Spec.new do |s|
  s.name               = "SocketRocket"
  s.version            = '1.1.1'
  s.authors            = 'Square'
  s.source_files       = 'SocketRocket/*.{h,m,c}'
  s.requires_arc       = true
  s.ios.frameworks     = %w{CFNetwork Security}
  s.osx.frameworks     = %w{CoreServices Security}
  s.osx.compiler_flags = '-Wno-format'
  s.libraries          = "icucore"
end
