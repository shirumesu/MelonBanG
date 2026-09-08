Pod::Spec.new do |s|
  s.name = 'libtorrent_flutter'
  s.version = '2.0.0'
  s.summary = 'Patched native libtorrent bridge for macOS.'
  s.homepage = 'https://github.com/ayman708-UX/libtorrent_flutter'
  s.license = { :file => '../LICENSE' }
  s.author = 'libtorrent_flutter contributors'
  s.source = { :path => '.' }
  s.platform = :osx, '26.0'
  s.dependency 'FlutterMacOS'
  unless system('/bin/bash', File.join(__dir__, 'build.sh'))
    raise 'Failed to build libtorrent. Install cmake, ninja and libtorrent-rasterbar with Homebrew.'
  end
  s.vendored_libraries = 'Libraries/*.dylib'
end
