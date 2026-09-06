cmake_minimum_required(VERSION 3.14)
project(libtorrent_flutter LANGUAGES CXX)
find_package(LibtorrentRasterbar CONFIG REQUIRED)
add_library(libtorrent_flutter SHARED ../src/torrent_bridge.cpp)
target_compile_features(libtorrent_flutter PRIVATE cxx_std_17)
target_compile_definitions(libtorrent_flutter PRIVATE
  TORRENT_BRIDGE_EXPORTS WIN32_LEAN_AND_MEAN NOMINMAX _WIN32_WINNT=0x0A00
)
target_compile_options(libtorrent_flutter PRIVATE /W3 /utf-8 /bigobj)
target_link_libraries(libtorrent_flutter PRIVATE
  LibtorrentRasterbar::torrent-rasterbar ws2_32 crypt32 iphlpapi
)
set(libtorrent_flutter_bundled_libraries $<TARGET_FILE:libtorrent_flutter> PARENT_SCOPE)
