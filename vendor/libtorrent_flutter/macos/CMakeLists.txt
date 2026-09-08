cmake_minimum_required(VERSION 3.24)
if(POLICY CMP0167)
  cmake_policy(SET CMP0167 NEW)
endif()
project(libtorrent_flutter LANGUAGES CXX)

find_package(LibtorrentRasterbar 2.1 CONFIG REQUIRED)
add_library(libtorrent_flutter SHARED ../src/torrent_bridge.cpp)
target_compile_features(libtorrent_flutter PRIVATE cxx_std_17)
target_link_libraries(libtorrent_flutter PRIVATE LibtorrentRasterbar::torrent-rasterbar)
set_target_properties(libtorrent_flutter PROPERTIES
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH "@loader_path"
)

install(TARGETS libtorrent_flutter
  RUNTIME_DEPENDENCY_SET torrent_dependencies
  LIBRARY DESTINATION .
)
install(RUNTIME_DEPENDENCY_SET torrent_dependencies
  PRE_EXCLUDE_REGEXES "^/usr/lib/" "^/System/Library/"
  POST_EXCLUDE_REGEXES "^/usr/lib/" "^/System/Library/"
  LIBRARY DESTINATION .
)
